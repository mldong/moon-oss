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
      code: @error.xml_error_code(text),
      message: or_empty(@error.xml_first(text, "Message")),
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
fn transport_text(err : @transport.TransportError) -> String {
  match err {
    @transport.TransportError::Network(detail) => "network: " + detail
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(detail) =>
      "invalid request: " + detail
    @transport.TransportError::InvalidResponse(detail) =>
      "invalid response: " + detail
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
/// 成功分支的正文读数：调用方只要文本（列举、拷贝回执）。
async fn response_body_text(
  body : &@transport.ResponseBody,
  status : Int32,
) -> String raise @error.OssError {
  let raw = read_all(body)
  body.close()
  response_text(raw, status)
}
