///|
/// 传输加速：`GET/PUT /?transferAcceleration`（官方 Go V2
/// `api_op_bucket_transferacceleration.go`，2026-10-22 现读）。开关只有 `Enabled`
/// 一个布尔；未配置时读口常见 404/NoSuchTransferAcceleration，落成 `None`。
pub(all) struct TransferAccelerationConfig {
  enabled : Bool
}

///|
pub async fn Client::put_bucket_transfer_acceleration(
  self : Client,
  bucket : String,
  config : TransferAccelerationConfig,
) -> Unit raise @error.OssError {
  let document = acceleration_document(config.enabled)
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("transferAcceleration", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
fn acceleration_document(enabled : Bool) -> String {
  "<TransferAccelerationConfiguration><Enabled>" +
  enabled.to_string() +
  "</Enabled></TransferAccelerationConfiguration>"
}

///|
pub async fn Client::get_bucket_transfer_acceleration(
  self : Client,
  bucket : String,
) -> TransferAccelerationConfig? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[
    ("transferAcceleration", ""),
  ]) catch {
    err =>
      match err {
        @error.OssError::Service(details) =>
          if details.status == 404 {
            return None
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  Some(TransferAccelerationConfig::{
    enabled: xml_first(body, "Enabled") == Some("true"),
  })
}
