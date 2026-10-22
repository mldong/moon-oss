///|
/// 表单上传（PostObject）。与 `put_object` 是两条服务端入口：这一条不走 `Authorization`
/// 头，凭据放在 multipart 字段里。
///
/// 默认走 **V4 表单签名**（`x-oss-signature-version: OSS4-HMAC-SHA256` 那一族，
/// 2026-10-22 按官方 Go V2 `sample/post_object.go` 现读）；`signature_version="v1"`
/// 保留旧的 `OSSAccessKeyId` + `Signature` 形状。`success_action_status` 默认 204，
/// 只接受 200/201/204。
pub async fn Client::post_object(
  self : Client,
  bucket : String,
  key : String,
  data : Bytes,
  content_type~ : String = "",
  metadata~ : Array[(String, String)] = [],
  acl~ : String = "",
  storage_class~ : String = "",
  expires_sec~ : Int64 = 3600L,
  success_action_status~ : Int32 = 204,
  filename~ : String = "",
  signature_version~ : String = "v4",
) -> PostObjectResult raise @error.OssError {
  if key.is_empty() {
    raise @error.BadParam("post_object key must not be empty")
  }
  if expires_sec <= 0L {
    raise @error.BadParam("post_object expires_sec must be positive")
  }
  if signature_version != "v1" && signature_version != "v4" {
    raise @error.BadParam(
      "signature_version must be v1 or v4, got " + signature_version,
    )
  }
  if success_action_status != 200 &&
    success_action_status != 201 &&
    success_action_status != 204 {
    raise @error.BadParam(
      "success_action_status must be 200, 201 or 204, got " +
      success_action_status.to_string(),
    )
  }
  reject_crlf("key", key)
  reject_crlf("content_type", content_type)
  reject_crlf("acl", acl)
  reject_crlf("storage_class", storage_class)
  for pair in metadata {
    reject_crlf("metadata key", pair.0)
    reject_crlf("metadata value", pair.1)
  }
  let millis = @auth.now_millis()
  let timestamp = @auth.iso8601_basic(millis)
  let date = timestamp[0:8].to_owned()
  let region = self.config.region_of()
  let credential = self.config.credentials().access_key() +
    "/" +
    date +
    "/" +
    region +
    "/oss/aliyun_v4_request"
  let policy_json = post_policy_document(
    bucket~,
    key~,
    content_type~,
    metadata~,
    acl~,
    storage_class~,
    success_action_status~,
    millis=millis + expires_sec * 1000L,
    signature_version~,
    timestamp~,
    credential~,
  )
  let policy = @base64.encode(@utf8.encode(policy_json.view()).exact_view())
  let fields : Array[(String, String)] = [("key", key), ("policy", policy)]
  if signature_version == "v4" {
    let signature = self.config
      .credentials()
      .post_policy_signature_v4(policy, date, region)
    fields.push(("x-oss-signature-version", "OSS4-HMAC-SHA256"))
    fields.push(("x-oss-credential", credential))
    fields.push(("x-oss-date", timestamp))
    fields.push(("x-oss-signature", signature))
  } else {
    let signature = self.config.credentials().post_policy_signature(policy)
    fields.push(("OSSAccessKeyId", self.config.credentials().access_key()))
    fields.push(("Signature", signature))
  }
  if !content_type.is_empty() {
    fields.push(("Content-Type", content_type))
  }
  if !acl.is_empty() {
    fields.push(("x-oss-object-acl", acl))
  }
  if !storage_class.is_empty() {
    fields.push(("x-oss-storage-class", storage_class))
  }
  if success_action_status != 204 {
    fields.push(("success_action_status", success_action_status.to_string()))
  }
  for pair in metadata {
    fields.push(("x-oss-meta-" + pair.0, pair.1))
  }
  let upload_name = if filename.is_empty() {
    safe_filename(key)
  } else {
    reject_crlf("filename", filename)
    sanitize_filename(filename)
  }
  let boundary = "----moonoss" +
    @auth.now_millis().to_string() +
    "-" +
    key.length().to_string()
  let form = post_form_body(boundary, fields, data, content_type, upload_name)
  let response = self.transport.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url: self.config.url_of(bucket),
    headers: [
      @transport.Header::{
        name: "content-type",
        value: "multipart/form-data; boundary=" + boundary,
      },
    ],
    body: @transport.RequestBody::Bytes(form),
  }) catch {
    err => raise @error.Network(transport_text(err))
  }
  let text = response_body_text(response.body, response.status)
  if response.status >= 200 && response.status < 300 {
    let header_etag = header_of(response.headers, "etag")
    let etag = match header_etag {
      Some(value) => Some(value)
      None => if text.is_empty() { None } else { xml_first(text, "ETag") }
    }
    let location = if text.is_empty() {
      None
    } else {
      xml_first(text, "Location")
    }
    let result_key = if text.is_empty() { None } else { xml_first(text, "Key") }
    PostObjectResult::{
      status: response.status,
      etag,
      location,
      key: result_key,
      body: text,
    }
  } else {
    raise @error.Service(@error.ServiceError::{
      status: response.status,
      code: xml_error_code(text),
      message: or_empty(xml_first(text, "Message")),
      request_id: header_of(response.headers, "x-oss-request-id"),
    })
  }
}

///|
fn reject_crlf(label : String, value : String) -> Unit raise @error.OssError {
  if value.contains("\r") || value.contains("\n") {
    raise @error.BadParam(label + " must not contain CR or LF")
  }
}

///|
fn json_quote(value : String) -> String {
  let mut out = "\""
  for ch in value {
    match ch {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      _ => out = out + ch.to_string()
    }
  }
  out + "\""
}

///|
/// policy 的 `expiration` 是带毫秒的 ISO8601 UTC；`iso8601_basic` 给的是
/// `YYYYMMDDTHHMMSSZ`，这里按位重排，不读本机时区。
fn post_policy_expiration(millis : Int64) -> String raise @error.OssError {
  let basic = @auth.iso8601_basic(millis)
  basic[0:4].to_owned() +
  "-" +
  basic[4:6].to_owned() +
  "-" +
  basic[6:8].to_owned() +
  "T" +
  basic[9:11].to_owned() +
  ":" +
  basic[11:13].to_owned() +
  ":" +
  basic[13:15].to_owned() +
  ".000Z"
}

///|
fn post_policy_document(
  bucket~ : String,
  key~ : String,
  content_type~ : String,
  metadata~ : Array[(String, String)],
  acl~ : String,
  storage_class~ : String,
  success_action_status~ : Int32,
  millis~ : Int64,
  signature_version~ : String,
  timestamp~ : String,
  credential~ : String,
) -> String raise @error.OssError {
  let conditions : Array[String] = [
    "[\"eq\",\"$key\"," + json_quote(key) + "]",
    "[\"eq\",\"$bucket\"," + json_quote(bucket) + "]",
  ]
  if signature_version == "v4" {
    conditions.push(
      "[\"eq\",\"$x-oss-signature-version\",\"OSS4-HMAC-SHA256\"]",
    )
    conditions.push(
      "[\"eq\",\"$x-oss-credential\"," + json_quote(credential) + "]",
    )
    conditions.push("[\"eq\",\"$x-oss-date\"," + json_quote(timestamp) + "]")
  }
  if !content_type.is_empty() {
    conditions.push(
      "[\"eq\",\"$Content-Type\"," + json_quote(content_type) + "]",
    )
  }
  if !acl.is_empty() {
    conditions.push("[\"eq\",\"$x-oss-object-acl\"," + json_quote(acl) + "]")
  }
  if !storage_class.is_empty() {
    conditions.push(
      "[\"eq\",\"$x-oss-storage-class\"," + json_quote(storage_class) + "]",
    )
  }
  if success_action_status != 204 {
    conditions.push(
      "[\"eq\",\"$success_action_status\"," +
      json_quote(success_action_status.to_string()) +
      "]",
    )
  }
  for pair in metadata {
    conditions.push(
      "[\"eq\"," +
      json_quote("$x-oss-meta-" + pair.0) +
      "," +
      json_quote(pair.1) +
      "]",
    )
  }
  "{\"expiration\":" +
  json_quote(post_policy_expiration(millis)) +
  ",\"conditions\":[" +
  conditions.join(",") +
  "]}"
}

///|
fn sanitize_filename(name : String) -> String {
  let mut out = ""
  for ch in name {
    match ch {
      '"' | '\\' | '\r' | '\n' => out = out + "_"
      _ => out = out + ch.to_string()
    }
  }
  if out.is_empty() {
    "object"
  } else {
    out
  }
}

///|
fn safe_filename(key : String) -> String {
  let parts = key.split("/")
  let mut last = "object"
  for part in parts {
    if !part.is_empty() {
      last = part.to_owned()
    }
  }
  sanitize_filename(last)
}

///|
fn post_form_body(
  boundary : String,
  fields : Array[(String, String)],
  data : Bytes,
  content_type : String,
  filename : String,
) -> Bytes {
  let parts : Array[Byte] = []
  for pair in fields {
    let head = "--" +
      boundary +
      "\r\nContent-Disposition: form-data; name=\"" +
      pair.0 +
      "\"\r\n\r\n" +
      pair.1 +
      "\r\n"
    parts.append(@utf8.encode(head.view()).to_array())
  }
  let file_type = if content_type.is_empty() {
    "application/octet-stream"
  } else {
    content_type
  }
  let file_head = "--" +
    boundary +
    "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"" +
    filename +
    "\"\r\nContent-Type: " +
    file_type +
    "\r\n\r\n"
  parts.append(@utf8.encode(file_head.view()).to_array())
  parts.append(data.to_array())
  parts.append(@utf8.encode("\r\n--" + boundary + "--\r\n").to_array())
  Bytes::from_array(parts)
}
