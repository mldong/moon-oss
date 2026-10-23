///|
/// 桶元信息三件：`GET /?location`、`GET /?bucketInfo`、`GET/PUT /?requestPayment`
/// （官方 Go V2 `api_op_bucket.go:659-1302`，2026-10-22 现读）。
/// 桶信息只取常用的地域／存储类／创建时间／拥有者；其余字段留在 `body` 原文里。
pub(all) struct BucketInfo {
  body : String
  region : String?
  storage_class : String?
  creation_date : String?
  owner_id : String?
}

///|
pub async fn Client::get_bucket_location(
  self : Client,
  bucket : String,
) -> String? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("location", "")])
  let body = response_body_text(response.body, response.status)
  xml_first(body, "LocationConstraint")
}

///|
pub async fn Client::get_bucket_info(
  self : Client,
  bucket : String,
) -> BucketInfo raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("bucketInfo", "")])
  let body = response_body_text(response.body, response.status)
  bucket_info_of(body)
}

///|
fn bucket_info_of(body : String) -> BucketInfo {
  // 服务端把字段包在 `<BucketInfo><Bucket>...` 里，地域叫 `Location` 而不是 `Region`。
  let inner = match xml_section_of(body, "Bucket") {
    Some(text) => text
    None => body
  }
  let owner = match xml_section_of(inner, "Owner") {
    Some(text) => text
    None => ""
  }
  BucketInfo::{
    region: xml_first(inner, "Location"),
    storage_class: xml_first(inner, "StorageClass"),
    creation_date: xml_first(inner, "CreationDate"),
    owner_id: xml_first(owner, "ID"),
    body,
  }
}

///|
pub async fn Client::get_bucket_request_payment(
  self : Client,
  bucket : String,
) -> String? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("requestPayment", "")])
  let body = response_body_text(response.body, response.status)
  xml_first(body, "Payer")
}

///|
pub async fn Client::put_bucket_request_payment(
  self : Client,
  bucket : String,
  payer : String,
) -> Unit raise @error.OssError {
  if payer != "BucketOwner" && payer != "Requester" {
    raise @error.BadParam(
      "payer must be BucketOwner or Requester, got " + payer,
    )
  }
  let document = payment_document(payer)
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("requestPayment", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
fn payment_document(payer : String) -> String {
  "<RequestPaymentConfiguration><Payer>" +
  xml_escape(payer) +
  "</Payer></RequestPaymentConfiguration>"
}
