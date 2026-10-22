///|
/// 桶日志：`GET/PUT/DELETE /?logging`。OSS 三家都有 DeleteBucketLogging，这一族
/// 按官方 XML `BucketLoggingStatus/LoggingEnabled` 读写；未开启时 `enabled` 为 `None`。
pub(all) struct BucketLogging {
  target_bucket : String
  target_prefix : String
}

///|
pub(all) struct BucketLoggingStatus {
  enabled : BucketLogging?
  body : String
}

///|
pub async fn Client::put_bucket_logging(
  self : Client,
  bucket : String,
  target_bucket : String,
  target_prefix~ : String = "",
) -> Unit raise @error.OssError {
  if target_bucket.is_empty() {
    raise @error.BadParam("logging target bucket is required")
  }
  let document = logging_document(target_bucket, target_prefix)
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("logging", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_logging(
  self : Client,
  bucket : String,
) -> BucketLoggingStatus raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("logging", "")])
  let body = response_body_text(response.body, response.status)
  parse_logging(body)
}

///|
pub async fn Client::delete_bucket_logging(
  self : Client,
  bucket : String,
) -> Unit raise @error.OssError {
  let response = request(self, "DELETE", bucket, query=[("logging", "")])
  discard_body(response)
}

///|
fn logging_document(target_bucket : String, target_prefix : String) -> String {
  "<BucketLoggingStatus><LoggingEnabled><TargetBucket>" +
  xml_escape(target_bucket) +
  "</TargetBucket><TargetPrefix>" +
  xml_escape(target_prefix) +
  "</TargetPrefix></LoggingEnabled></BucketLoggingStatus>"
}

///|
fn parse_logging(body : String) -> BucketLoggingStatus {
  let enabled = match xml_sections(body, "LoggingEnabled") {
    [] => None
    sections =>
      Some(BucketLogging::{
        target_bucket: or_empty(xml_first(sections[0], "TargetBucket")),
        target_prefix: or_empty(xml_first(sections[0], "TargetPrefix")),
      })
  }
  BucketLoggingStatus::{ enabled, body, }
}
