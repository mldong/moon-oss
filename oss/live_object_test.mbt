///|
// 对象族·分片·预签名的真桶档。六条待实测项里有四条只能在这里取读数：
// 中文键的编码、`x-oss-meta-*` 的回显、`x-oss-copy-source` 与无值 `?acl` 的形状、
// ListObjects V2 的元素名。
//
// Env: OSS_AK / OSS_SK / OSS_BUCKET / OSS_REGION。键一律 `moonfs-` 前缀 + 本次运行号，
// 测完即删——不留残件，也不与并发的另一轮撞名。

///|
fn run_tag() -> String {
  @auth.now_millis().to_string()
}

///|
fn bytes_of(text : String) -> Bytes {
  @utf8.encode(text.view())
}

///|
fn text_of(data : Bytes) -> String {
  @utf8.decode_lossy(data)
}

///|
fn or_blank(value : String?) -> String {
  match value {
    Some(v) => v
    None => ""
  }
}

///|
fn trim_at(text : String, limit : Int32) -> String {
  if text.length() <= limit {
    text
  } else {
    text[0:limit].to_owned() + "…"
  }
}

///|
fn transport_note(err : @transport.TransportError) -> String {
  match err {
    @transport.TransportError::Network(detail) => "network: " + detail
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(detail) =>
      "invalid-request: " + detail
    @transport.TransportError::InvalidResponse(detail) =>
      "invalid-response: " + detail
  }
}

///|
/// 错误读数串。`HEAD` 的 404 **没有 XML 正文**（真桶读数：`<Code>` 读不出，只有状态码），
/// 所以这一族只能退回状态码——不是"实现没解析出来"，是服务端没给。
/// 这条同时解释了为什么适配层判"对象不存在"要看 `status` 而不是只看 `code`。
fn error_code(err : @error.OssError) -> String {
  match err {
    @error.OssError::Service(details) =>
      if details.code.is_empty() {
        "status:" + details.status.to_string()
      } else {
        details.code
      }
    other => other.text()
  }
}

///|
/// 建一条本轮独有的键。`moonfs-` 前缀是 owner 在桶侧配生命周期规则认的那一条。
fn live_key(suffix : String) -> String {
  "moonfs-" + run_tag() + "-" + suffix
}

///|
/// 把响应体读空（测试侧自带一份：库内那一条是本包的私有件，黑盒档拿不到）。
async fn drain(
  body : &@transport.ResponseBody,
) -> Bytes raise @transport.TransportError {
  let merged : Array[Byte] = []
  let mut reading = true
  while reading {
    let chunk = body.read(65536)
    match chunk {
      Some(data) => merged.append(data.to_array())
      None => reading = false
    }
  }
  Bytes::from_array(merged)
}

///|
/// 不带凭据打开一条 URL（预签名那一档的验证姿势：客户端一字不加）。
async fn open_url(
  url : String,
  verb~ : String = "GET",
  headers~ : Array[(String, String)] = [],
  payload~ : Bytes = @utf8.encode("".view()),
) -> (Int32, String) {
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  let wire : Array[@transport.Header] = []
  for pair in headers {
    wire.push(@transport.Header::{ name: pair.0, value: pair.1, })
  }
  let http_method : @transport.Method = match verb {
    "PUT" => @transport.Method::Put
    _ => @transport.Method::Get
  }
  let request_body : @transport.RequestBody = if payload.length() == 0 {
    @transport.RequestBody::Empty
  } else {
    @transport.RequestBody::Bytes(payload)
  }
  let response = transport.send(@transport.Request::{
    http_method,
    url,
    headers: wire,
    body: request_body,
  }) catch {
    err => return (0, "transport: " + transport_note(err))
  }
  let body = drain(response.body) catch {
    err => return (response.status, "read: " + transport_note(err))
  }
  response.body.close()
  (response.status, text_of(body))
}

///|
async test "真端点·对象族：写→查→读→范围读→删，元数据回显与中文键" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let bucket = environment.2
      let key = live_key("中文键.txt")
      let payload = "moon-oss 对象族真桶读数\nsecond line"
      let written = bytes_of(payload)
      let put = client.put_object(
        bucket,
        key,
        written,
        content_type="text/plain; charset=utf-8",
        metadata=[("tool", "moon-oss")],
      ) catch {
        err => fail("put_object: " + err.text())
      }
      println("put etag=" + put.etag)
      if put.etag.is_empty() {
        fail("put_object must echo the ETag header")
      }

      let stat = client.stat_object(bucket, key) catch {
        err => fail("stat_object: " + err.text())
      }
      println(
        "stat size=" +
        stat.size.to_string() +
        " ctype=" +
        or_blank(stat.content_type) +
        " meta=" +
        pairs_note(stat.metadata),
      )
      // 比的是**字节数**不是字符串长度：那一行中文差 3 个字节，比错就会把
      // "内容被截断了"读成"大小一致"。
      assert_eq(stat.size, written.length().to_int64())
      if !has_pair(stat.metadata, "tool", "moon-oss") {
        fail("x-oss-meta-* must come back: " + pairs_note(stat.metadata))
      }

      let got = client.get_object(bucket, key) catch {
        err => fail("get_object: " + err.text())
      }
      assert_eq(text_of(got.body), payload)

      let part = client.get_object(bucket, key, range="bytes=0-3") catch {
        err => fail("range get: " + err.text())
      }
      println("range bytes=" + part.body.length().to_string())
      assert_eq(part.body.length(), 4)
      if part.content_range is None {
        fail("a ranged read must carry Content-Range")
      }

      let _ = client.delete_object(bucket, key) catch {
        err => fail("delete_object: " + err.text())
      }
      let after = probe_stat_code(client, bucket, key)
      println("after delete stat=" + after)
      assert_eq(after, "status:404")
    }
  }
}

///|
async test "真端点·复制与对象 ACL：x-oss-copy-source 与无值 ?acl 都要签得上" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let bucket = environment.2
      let source = live_key("copy-source.txt")
      let target = live_key("copy-target.txt")
      let _ = client.put_object(bucket, source, bytes_of("copy me")) catch {
        err => fail("put source: " + err.text())
      }
      let copy = client.copy_object(bucket, source, bucket, target) catch {
        err => fail("copy_object: " + err.text())
      }
      println("copy etag=" + copy.etag)
      if copy.etag.is_empty() {
        fail("copy reply must carry an ETag: " + trim_at(copy.body, 200))
      }
      let copied = client.get_object(bucket, target) catch {
        err => fail("get copy: " + err.text())
      }
      assert_eq(text_of(copied.body), "copy me")

      let before = client.get_object_acl(bucket, target) catch {
        err => fail("get_object_acl(default): " + err.text())
      }
      println("acl default grant=" + before.grant)
      // 写侧两档都试：公开读被桶侧拦（真桶读数 403 AccessDenied
      // "Put public object acl is not allowed"），private 才是这一族一定能用的那一档。
      // 这一档要裁决的是签名，不是权限：读回 `SignatureDoesNotMatch` 才算失败。
      let public_note = try_acl(client, bucket, target, "public-read")
      println("put_object_acl(public-read) -> " + public_note)
      let private_note = try_acl(client, bucket, target, "private")
      println("put_object_acl(private) -> " + private_note)
      if private_note == "SignatureDoesNotMatch" ||
        public_note == "SignatureDoesNotMatch" {
        fail("the value-less ?acl must sign as its bare name: " + private_note)
      }
      let _ = client.delete_object(bucket, source) catch {
        err => fail("delete source: " + err.text())
      }
      let _ = client.delete_object(bucket, target) catch {
        err => fail("delete target: " + err.text())
      }
    }
  }
}

///|
async test "真端点·预签名 URL：GET 免凭据可取，PUT 直传可落" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let bucket = environment.2
      let key = live_key("presign-get.txt")
      let _ = client.put_object(bucket, key, bytes_of("presigned payload")) catch {
        err => fail("put: " + err.text())
      }
      let url = client.presigned_get_url(bucket, key, expires_sec=120L) catch {
        err => fail("presigned_get_url: " + err.text())
      }
      // URL 里带着签名，日志只打长度——签名串本身是一条可用的下载凭据。
      println("presigned get url length=" + url.length().to_string())
      let (status, body) = open_url(url)
      println("presigned get status=" + status.to_string())
      assert_eq(status, 200)
      assert_eq(body, "presigned payload")

      let put_key = live_key("presign-put.txt")
      let put_url = client.presigned_put_url(
        bucket,
        put_key,
        expires_sec=120L,
        content_type="text/plain",
      ) catch {
        err => fail("presigned_put_url: " + err.text())
      }
      let (put_status, put_body) = open_url(
        put_url,
        verb="PUT",
        headers=[("content-type", "text/plain")],
        payload=bytes_of("direct upload"),
      )
      println(
        "presigned put status=" +
        put_status.to_string() +
        " body=" +
        trim_at(put_body, 160),
      )
      assert_eq(put_status, 200)
      let landed = client.stat_object(bucket, put_key) catch {
        err => fail("stat after presigned put: " + err.text())
      }
      assert_eq(landed.size, 13L)
      let _ = client.delete_object(bucket, key) catch {
        err => fail("delete get-key: " + err.text())
      }
      let _ = client.delete_object(bucket, put_key) catch {
        err => fail("delete put-key: " + err.text())
      }
    }
  }
}

///|
async test "真端点·分片族五步：两片尺寸、合并大小、放弃后 NoSuchUpload" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let bucket = environment.2
      let key = live_key("multipart.bin")
      let part_size = 256 * 1024
      let first = make_part(1, part_size)
      let second = make_part(2, part_size)
      let upload_id = client.create_multipart_upload(
        bucket,
        key,
        content_type="application/octet-stream",
      ) catch {
        err => fail("create: " + err.text())
      }
      println("upload id length=" + upload_id.length().to_string())
      let etag1 = client.upload_part(bucket, key, upload_id, 1, first) catch {
        err => fail("upload_part 1: " + err.text())
      }
      let etag2 = client.upload_part(bucket, key, upload_id, 2, second) catch {
        err => fail("upload_part 2: " + err.text())
      }
      let page = client.list_parts(bucket, key, upload_id) catch {
        err => fail("list_parts: " + err.text())
      }
      println("list_parts count=" + page.parts.length().to_string())
      assert_eq(page.parts.length(), 2)
      assert_eq(page.parts[0].part_number, 1)
      assert_eq(page.parts[1].size, part_size.to_int64())
      let final_etag = client.complete_multipart_upload(
        bucket,
        key,
        upload_id,
        [(1, etag1), (2, etag2)],
      ) catch {
        err => fail("complete: " + err.text())
      }
      println("complete etag=" + final_etag)
      let merged = client.stat_object(bucket, key) catch {
        err => fail("stat after complete: " + err.text())
      }
      assert_eq(merged.size, (part_size * 2).to_int64())
      let _ = client.delete_object(bucket, key) catch {
        err => fail("delete merged: " + err.text())
      }

      // 负向：放弃之后再查分片必须回 `NoSuchUpload`，不能"看起来是空列表"。
      let doomed = live_key("abort-me.bin")
      let doomed_id = client.create_multipart_upload(bucket, doomed) catch {
        err => fail("create for abort: " + err.text())
      }
      let _ = client.abort_multipart_upload(bucket, doomed, doomed_id) catch {
        err => fail("abort: " + err.text())
      }
      let reading = probe_parts_code(client, bucket, doomed, doomed_id)
      println("after abort list_parts=" + trim_at(reading, 120))
      assert_eq(reading, "NoSuchUpload")
    }
  }
}

///|
/// 待实测项第 5 条：V2 回包的元素名与续页字段。这一条用**列举的真读数**判断而不是用文档——
/// 元素名读错会得到"这个桶是空的"那种自洽的错读数。
async test "真端点·列举 V2 元素名：一行对象要同时拿到键、大小、ETag、时刻" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let bucket = environment.2
      let prefix = "moonfs-" + run_tag()
      let key_a = prefix + "-a.txt"
      let key_b = prefix + "-b.txt"
      let _ = client.put_object(bucket, key_a, bytes_of("aaa")) catch {
        err => fail("put a: " + err.text())
      }
      let _ = client.put_object(bucket, key_b, bytes_of("bbbb")) catch {
        err => fail("put b: " + err.text())
      }
      let listing = client.list_objects(bucket, prefix~, max_keys=10) catch {
        err => fail("list: " + err.text())
      }
      let keys : Array[String] = []
      for item in listing.objects {
        keys.push(item.key)
      }
      println("listed " + keys.join(", "))
      assert_true(keys.length() >= 2)
      let first = listing.objects[0]
      println(
        "row size=" +
        first.size.to_string() +
        " etag=" +
        or_blank(first.etag) +
        " last_modified=" +
        or_blank(first.last_modified),
      )
      assert_true(first.size > 0L)
      if or_blank(first.etag).length() < 32 {
        fail(
          "ETag must be a 32-hex (or -N suffixed) string: " +
          or_blank(first.etag),
        )
      }
      if first.last_modified is None {
        fail("LastModified missing: " + trim_at(listing.body, 300))
      }
      let _ = client.delete_object(bucket, key_a) catch {
        err => fail("delete a: " + err.text())
      }
      let _ = client.delete_object(bucket, key_b) catch {
        err => fail("delete b: " + err.text())
      }
    }
  }
}

///|
/// "读不到就报错"这一族要用**状态码**判断，不能让 try 那臂回结构体、catch 那臂回字符串——
/// MoonBit 的 `expr catch` 两侧必须同型，所以分叉放在一个返回 String 的小函数里。
async fn probe_stat_code(
  client : @oss.Client,
  bucket : String,
  key : String,
) -> String {
  let stat = client.stat_object(bucket, key) catch {
    err => return error_code(err)
  }
  "ok:" + stat.size.to_string()
}

///|
async fn probe_parts_code(
  client : @oss.Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> String {
  let page = client.list_parts(bucket, key, upload_id) catch {
    err => return error_code(err)
  }
  "ok:" + page.parts.length().to_string()
}

///|
/// ACL 写的读数：成功报 `ok`，被拒报服务端 `<Code>`。
async fn try_acl(
  client : @oss.Client,
  bucket : String,
  key : String,
  acl : String,
) -> String {
  client.put_object_acl(bucket, key, acl) catch {
    err => return error_code(err)
  }
  "ok"
}

///|
/// 与 `metadata~` 入参同一坐标系的读数串，只为打印用。
fn pairs_note(pairs : Array[(String, String)]) -> String {
  let parts : Array[String] = []
  for pair in pairs {
    parts.push(pair.0 + "=" + pair.1)
  }
  parts.join(" ")
}

///|
fn make_part(number : Int32, size : Int32) -> Bytes {
  let mark = if number == 1 { 'a' } else { 'b' }
  let chars : Array[Char] = []
  for _ in 0..<size {
    chars.push(mark)
  }
  bytes_of(String::from_array(chars))
}

///|
fn has_pair(
  pairs : Array[(String, String)],
  name : String,
  value : String,
) -> Bool {
  let mut found = false
  for pair in pairs {
    if pair.0 == name && pair.1 == value {
      found = true
    }
  }
  found
}
