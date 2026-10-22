///|
/// 分片族的两个补件：分片复制（`UploadPartCopy`）与未完成分片列举（`ListMultipartUploads`）。
/// 两者都复用现有 `request` 链，不新开签名/传输路径。

///|
/// `PUT /<key>?partNumber=N&uploadId=...`，数据不从本地上传，而是从源对象按范围复制。
/// `copy_source_range~` 收 HTTP Range 原值（如 `bytes=0-1023`），与 `get_object` 的 `range~`
/// 同一条纪律：SDK 不翻译范围语法。
pub async fn Client::upload_part_copy(
  self : Client,
  source_bucket : String,
  source_key : String,
  bucket : String,
  key : String,
  upload_id : String,
  part_number : Int32,
  copy_source_range~ : String = "",
  copy_source_if_match~ : String = "",
  copy_source_if_none_match~ : String = "",
  copy_source_if_modified_since~ : String = "",
  copy_source_if_unmodified_since~ : String = "",
) -> UploadPartCopyResult raise @error.OssError {
  check_part_number(part_number)
  if upload_id.is_empty() {
    raise @error.BadParam("upload id is required")
  }
  let conditions = copy_source_conditional_headers(
    if_match=copy_source_if_match,
    if_none_match=copy_source_if_none_match,
    if_modified_since=copy_source_if_modified_since,
    if_unmodified_since=copy_source_if_unmodified_since,
  )
  let headers : Array[(String, String)] = [
    ("x-oss-copy-source", copy_source_of(source_bucket, source_key)),
  ]
  if !copy_source_range.is_empty() {
    headers.push(("x-oss-copy-source-range", copy_source_range))
  }
  headers.append(conditions)
  let response = request(
    self,
    "PUT",
    bucket,
    key~,
    query=[("partNumber", part_number.to_string()), ("uploadId", upload_id)],
    extra_headers=headers,
  )
  let body = response_body_text(response.body, response.status)
  parse_upload_part_copy_result(body, response.headers)
}

///|
/// `GET /?uploads`：列未完成的分片任务。与 `list_objects` 同形按 `<Upload>` 切段，
/// 避免 `xml_all("Key")` 与 `xml_all("UploadId")` 两列长度不等时错配。
pub async fn Client::list_multipart_uploads(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  delimiter~ : String = "",
  max_uploads~ : Int32 = 1000,
  key_marker~ : String = "",
  upload_id_marker~ : String = "",
) -> MultipartUploadListing raise @error.OssError {
  if max_uploads < 1 || max_uploads > 1000 {
    raise @error.BadParam(
      "max_uploads must be within 1..1000, got " + max_uploads.to_string(),
    )
  }
  let response = request(
    self,
    "GET",
    bucket,
    query=multipart_uploads_query(
      prefix~,
      delimiter~,
      max_uploads~,
      key_marker~,
      upload_id_marker~,
    ),
  )
  let body = response_body_text(response.body, response.status)
  parse_multipart_upload_listing(body)
}

///|
fn check_part_number(part_number : Int32) -> Unit raise @error.OssError {
  if part_number < 1 || part_number > 10000 {
    raise @error.BadParam(
      "part number must be within 1..10000, got " + part_number.to_string(),
    )
  }
}

///|
fn copy_source_of(source_bucket : String, source_key : String) -> String {
  "/" + source_bucket + "/" + @auth.uri_encode(source_key, keep_slash=true)
}

///|
fn multipart_uploads_query(
  prefix~ : String,
  delimiter~ : String,
  max_uploads~ : Int32,
  key_marker~ : String,
  upload_id_marker~ : String,
) -> Array[(String, String)] {
  let query : Array[(String, String)] = [
    ("uploads", ""),
    ("max-uploads", max_uploads.to_string()),
  ]
  add_param(query, "prefix", prefix)
  add_param(query, "delimiter", delimiter)
  add_param(query, "key-marker", key_marker)
  add_param(query, "upload-id-marker", upload_id_marker)
  query
}

///|
fn parse_upload_part_copy_result(
  body : String,
  headers : Array[@transport.Header],
) -> UploadPartCopyResult {
  let xml_etag = or_empty(xml_first(body, "ETag"))
  let etag = if xml_etag.is_empty() {
    or_empty(header_of(headers, "etag"))
  } else {
    xml_etag
  }
  UploadPartCopyResult::{
    etag,
    last_modified: xml_first(body, "LastModified"),
    body,
  }
}

///|
fn parse_multipart_upload_listing(body : String) -> MultipartUploadListing {
  let uploads : Array[MultipartUploadInfo] = []
  for section in xml_sections(body, "Upload") {
    uploads.push(MultipartUploadInfo::{
      key: or_empty(xml_first(section, "Key")),
      upload_id: or_empty(xml_first(section, "UploadId")),
      initiated: xml_first(section, "Initiated"),
    })
  }
  let prefixes : Array[String] = []
  for group in xml_sections(body, "CommonPrefixes") {
    prefixes.push(or_empty(xml_first(group, "Prefix")))
  }
  MultipartUploadListing::{
    uploads,
    common_prefixes: prefixes,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_key_marker: nonempty(xml_first(body, "NextKeyMarker")),
    next_upload_id_marker: nonempty(xml_first(body, "NextUploadIdMarker")),
    body,
  }
}

///|
fn nonempty(value : String?) -> String? {
  match value {
    Some(text) => if text.is_empty() { None } else { Some(text) }
    None => None
  }
}
