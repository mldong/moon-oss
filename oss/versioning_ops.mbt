///|
/// 桶版本控制：`GET/PUT /?versioning`。只收官方两档 `Enabled`/`Suspended`，
/// 别的字符串本地拒，避免把未知状态当成"开/关"。
pub async fn Client::put_bucket_versioning(
  self : Client,
  bucket : String,
  status : String,
) -> Unit raise @error.OssError {
  check_versioning_status(status)
  let document = "<VersioningConfiguration><Status>" +
    xml_escape(status) +
    "</Status></VersioningConfiguration>"
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("versioning", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_versioning(
  self : Client,
  bucket : String,
) -> String? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("versioning", "")])
  let body = response_body_text(response.body, response.status)
  xml_first(body, "Status")
}

///|
fn check_versioning_status(status : String) -> Unit raise @error.OssError {
  if status != "Enabled" && status != "Suspended" {
    raise @error.BadParam(
      "versioning status must be Enabled or Suspended, got " + status,
    )
  }
}
