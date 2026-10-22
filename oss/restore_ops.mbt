///|
/// 归档解冻：`POST /<key>?restore`，正文是 `RestoreRequest`。
/// `days` 是解冻后的可读天数；`tier` 为空就不发 `<Tier>`，由服务端取默认档。
pub async fn Client::restore_object(
  self : Client,
  bucket : String,
  key : String,
  days~ : Int32 = 1,
  tier~ : String = "",
) -> Unit raise @error.OssError {
  if days < 1 {
    raise @error.BadParam("restore days must be positive")
  }
  let document = restore_document(days, tier)
  let response = request(
    self,
    "POST",
    bucket,
    key~,
    query=[("restore", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
fn restore_document(days : Int32, tier : String) -> String {
  let mut out = "<RestoreRequest><Days>" + days.to_string() + "</Days>"
  if !tier.is_empty() {
    out = out + "<Tier>" + xml_escape(tier) + "</Tier>"
  }
  out + "</RestoreRequest>"
}
