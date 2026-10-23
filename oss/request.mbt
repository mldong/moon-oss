///|
/// 发一次已签名的请求，并把非 2xx 翻成 `OssError::Service`。
///
/// 三处形状值得说明：
/// · `host` **既不入签也不上海报**——OSS V4 的规范化头块不含 host（与 AWS SigV4 不同，
///   官方示例的头块里就没有那一行；真桶读数：把它算进去当场 `SignatureDoesNotMatch`）。
///   实际的 Host 头由传输层按 URL 自己写。
/// · 查询参数**全部**进签名串（V4 的规则，与 V1 的"只子资源入签"不同）。
/// · 发出去的查询串用的就是**规范化那一串**（编码后、排序后）。签名与实际不一致是
///   这一族最难查的错，所以不让两处各自拼一遍。
async fn request(
  client : Client,
  verb : String,
  bucket : String,
  key~ : String = "",
  query~ : Array[(String, String)] = [],
  extra_headers~ : Array[(String, String)] = [],
  body~ : @transport.RequestBody = @transport.RequestBody::Empty,
) -> @transport.Response raise @error.OssError {
  let config = client.config
  let extra_headers = match config.credentials().security_token() {
    Some(token) => extra_headers + [("x-oss-security-token", token)]
    None => extra_headers
  }
  let millis = @auth.now_millis()
  let timestamp = @auth.iso8601_basic(millis)
  let signed_headers : Array[(String, String)] = @auth.required_headers(
      timestamp,
    ) +
    extra_headers
  let signature = config
    .credentials()
    .sign_at(config.region_of(), millis, @auth.RequestToSign::{
      verb,
      canonical_uri: config.canonical_uri_of(bucket, key~),
      query,
      headers: signed_headers,
    })
  let canonical_query = @auth.canonical_query_string(query)
  let url = config.url_of(bucket, key~)
  let full_url = if canonical_query.is_empty() {
    url
  } else {
    url + "?" + canonical_query
  }
  let wire : Array[@transport.Header] = []
  for pair in @auth.required_headers(timestamp) + extra_headers {
    wire.push(@transport.Header::{ name: pair.0, value: pair.1, })
  }
  wire.push(@transport.Header::{
    name: "authorization",
    value: signature.authorization,
  })
  let http_method = method_of(verb)
  let response = client.transport.send(@transport.Request::{
    http_method,
    url: full_url,
    headers: wire,
    body,
  }) catch {
    err => raise @error.Network(transport_text(err))
  }
  if response.status >= 200 && response.status < 300 {
    response
  } else {
    let body_stream = response.body
    let text = response_body_text(body_stream, response.status)
    raise @error.Service(@error.ServiceError::{
      status: response.status,
      code: xml_error_code(text),
      message: or_empty(xml_first(text, "Message")),
      request_id: header_of(response.headers, "x-oss-request-id"),
    })
  }
}

///|
fn method_of(verb : String) -> @transport.Method raise @error.OssError {
  match verb {
    "GET" => @transport.Method::Get
    "HEAD" => @transport.Method::Head
    "PUT" => @transport.Method::Put
    "POST" => @transport.Method::Post
    "DELETE" => @transport.Method::Delete
    _ => raise @error.BadParam("unsupported verb: " + verb)
  }
}

///|
/// 问号之后一律隐去。传输层的 `InvalidRequest` 有几档会把整条 URL 原样写进文案
/// （hutool 的 `split_url`：`url 缺 :// 分隔`、`url 带 fragment`、`url 缺 authority`、
/// `pathless query` 四档都带），而预签名 URL 的 query **就是凭据本体**——
/// `x-oss-credential` 加一条 `x-oss-expires` 窗口内可用的 `x-oss-signature`，
/// 落进日志等于把这条授权又发出去一份。主机与路径留着：诊断要看的是"哪一发"，不是那把钥匙。
/// `Network` 那一档本来只到源站（`建连失败（scheme://authority）：…`），一并走这条
/// 是因为它没有代价；`InvalidResponse` 的文案由底座透上来，形状不由本库保证，同样隐去。
fn redact_query(text : String) -> String {
  match text.find("?") {
    None => text
    Some(at) => text[0:at].to_owned() + "?<redacted>"
  }
}

///|
/// 生产件里把传输层文案交给调用方的唯一通道：`request` 与 `read_all` 两个 catch 点都走这里，
/// 所以隐去只需要在这一处生效。新加 catch 点时别再手写 `"network: " + detail`。
fn transport_text(err : @transport.TransportError) -> String {
  match err {
    @transport.TransportError::Network(detail) =>
      "network: " + redact_query(detail)
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(detail) =>
      "invalid request: " + redact_query(detail)
    @transport.TransportError::InvalidResponse(detail) =>
      "invalid response: " + redact_query(detail)
  }
}

///|
fn or_empty(value : String?) -> String {
  match value {
    Some(v) => v
    None => ""
  }
}

///|
fn header_of(headers : Array[@transport.Header], name : String) -> String? {
  let want = name.to_lower()
  for h in headers {
    if h.name.to_lower() == want {
      return Some(h.value)
    }
  }
  None
}

///|
/// 把响应体读空。非 2xx 的分支也要读，否则除了状态码什么证据都没有。
async fn read_all(
  body : &@transport.ResponseBody,
) -> Bytes raise @error.OssError {
  let merged : Array[Byte] = []
  let mut reading = true
  while reading {
    let chunk = body.read(65536) catch {
      err => raise @error.Network(transport_text(err))
    }
    match chunk {
      Some(data) => merged.append(data.to_array())
      None => reading = false
    }
  }
  Bytes::from_array(merged)
}

///|
/// 本 SDK 全量读回的正文都按 UTF-8 解；解不开不是"网络断"也不是"服务端拒"，
/// 是这条应答本身没法用，所以单列 `BadResponse`，并把状态码带在文案里。
fn response_text(data : Bytes, status : Int32) -> String raise @error.OssError {
  @utf8.decode(data.exact_view()) catch {
    _ =>
      raise @error.BadResponse(
        "response body is not valid UTF-8, status " + status.to_string(),
      )
  }
}

///|
/// 读完并关掉响应体。**2xx 且不需要正文的那几条都必须走这一条**：
/// 传输层的池只收"读尽的线"，不读也不关等于把一条 TLS 连接晾在外面——
/// 真桶实测一轮二十几条请求时，晾着的连接会让后面的请求整等 30 秒再报 timeout。
async fn discard_body(
  response : @transport.Response,
) -> Unit raise @error.OssError {
  let body = response.body
  let _ = read_all(body)
  body.close()
}

///|
/// 成功分支的正文读数：调用方只要文本（列举、拷贝回执）。
async fn response_body_text(
  body : &@transport.ResponseBody,
  status : Int32,
) -> String raise @error.OssError {
  let raw = read_all(body)
  body.close()
  response_text(raw, status)
}
