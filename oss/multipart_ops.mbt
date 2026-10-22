///|
/// 手动分片族五步。这条线与"整对象一次写"是两套服务端形状，所以两边要分开测——
/// 尤其**分片下限**：OSS 除最后一片外每片不得小于 100KB（官方现读），
/// 而存储契约的分片档本来就是 5 MiB，所以这条腿不需要为契约改任何参数。

///|
pub(all) struct PartInfo {
  part_number : Int32
  etag : String
  size : Int64
}

///|
pub(all) struct PartPage {
  parts : Array[PartInfo]
  is_truncated : Bool
  /// 续页用的分片号；回包没给就是"到底了"
  next_part_number_marker : String?
  body : String
}

///|
/// `POST /<key>?uploads`。`uploads` 是无值参数——与 `?acl` 同一族形状。
pub async fn Client::create_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  content_type~ : String = "",
  metadata~ : Array[(String, String)] = [],
  storage_class~ : String = "",
) -> String raise @error.OssError {
  let response = request(
    self,
    "POST",
    bucket,
    key~,
    query=[("uploads", "")],
    extra_headers=object_headers(content_type~, metadata~, storage_class~),
  )
  let body = response_body_text(response.body, response.status)
  match xml_first(body, "UploadId") {
    Some(id) =>
      if id.is_empty() {
        raise @error.BadResponse(
          "initiate response has an empty UploadId: " + body,
        )
      } else {
        id
      }
    None =>
      raise @error.BadResponse("initiate response carries no UploadId: " + body)
  }
}

///|
/// 分片号从 1 起。越界在**发出请求之前**拒：让服务端去猜一个 0 号分片，
/// 收到的会是一条看不出根因的错。
pub async fn Client::upload_part(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
  part_number : Int32,
  data : Bytes,
  content_md5~ : String = "",
  compute_md5~ : Bool = false,
) -> String raise @error.OssError {
  check_part_number(part_number)
  if upload_id.is_empty() {
    raise @error.BadParam("upload id is required")
  }
  if compute_md5 && !content_md5.is_empty() {
    raise @error.BadParam("content_md5 and compute_md5 are mutually exclusive")
  }
  let md5 = if compute_md5 { content_md5_of(data) } else { content_md5 }
  let headers : Array[(String, String)] = []
  if !md5.is_empty() {
    headers.push(("content-md5", md5))
  }
  let response = request(
    self,
    "PUT",
    bucket,
    key~,
    query=[("partNumber", part_number.to_string()), ("uploadId", upload_id)],
    extra_headers=headers,
    body=@transport.RequestBody::Bytes(data),
  )
  discard_body(response)
  match header_of(response.headers, "etag") {
    Some(etag) => etag
    None => raise @error.BadResponse("upload_part reply has no ETag header")
  }
}

///|
pub async fn Client::list_parts(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
  part_number_marker~ : Int32 = 0,
) -> PartPage raise @error.OssError {
  let query : Array[(String, String)] = [("uploadId", upload_id)]
  if part_number_marker > 0 {
    query.push(("part-number-marker", part_number_marker.to_string()))
  }
  let response = request(self, "GET", bucket, key~, query~)
  let body = response_body_text(response.body, response.status)
  let parts : Array[PartInfo] = []
  for section in xml_sections(body, "Part") {
    parts.push(PartInfo::{
      part_number: parse_int32(or_empty(xml_first(section, "PartNumber"))),
      etag: or_empty(xml_first(section, "ETag")),
      size: parse_int64(or_empty(xml_first(section, "Size"))),
    })
  }
  PartPage::{
    parts,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_part_number_marker: xml_first(body, "NextPartNumberMarker"),
    body,
  }
}

///|
/// 完成：分片必须**按号升序**列出，且除最后一片外每片不小于 100KB。
/// 顺序这里不重新排——排了就会把"调用方给的顺序不对"这个真错藏起来。
pub async fn Client::complete_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
  parts : Array[(Int32, String)],
) -> String raise @error.OssError {
  if parts.is_empty() {
    raise @error.BadParam("complete needs at least one part")
  }
  let response = request(
    self,
    "POST",
    bucket,
    key~,
    query=[("uploadId", upload_id)],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(
      @utf8.encode(complete_document(parts).view()),
    ),
  )
  let body = response_body_text(response.body, response.status)
  or_empty(xml_first(body, "ETag"))
}

///|
pub async fn Client::abort_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> Unit raise @error.OssError {
  let response = request(self, "DELETE", bucket, key~, query=[
    ("uploadId", upload_id),
  ])
  discard_body(response)
}

///|
fn complete_document(parts : Array[(Int32, String)]) -> String {
  let mut out = "<CompleteMultipartUpload>"
  for pair in parts {
    let number = pair.0.to_string()
    let quoted = xml_escape(pair.1)
    out = out +
      "<Part><PartNumber>" +
      number +
      "</PartNumber><ETag>" +
      quoted +
      "</ETag></Part>"
  }
  out + "</CompleteMultipartUpload>"
}

///|
fn parse_int32(text : String) -> Int32 {
  @string.parse_int(text.view(), base=10) catch {
    _ => 0
  }
}
