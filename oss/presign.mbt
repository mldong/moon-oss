///|
/// 预签名 URL 两条。查询串签名与 Header 签名共用 `auth` 那一套规范化算法，
/// 差别只在凭据进参数还是进头（见 `auth/presign.mbt`）。

///|
/// 免凭据下载 URL。签好之后**任何**持有它的人都能取——有效期就是唯一的控制面，
/// 所以上限由签名那层把关，不在这里放宽。
pub fn Client::presigned_get_url(
  self : Client,
  bucket : String,
  key : String,
  expires_sec~ : Int64 = 600L,
) -> String raise @error.OssError {
  self.presigned_url("GET", bucket, key~, expires_sec~, content_type="")
}

///|
/// 前端直传 URL。`content_type~` 一旦给定就要**原样**随上传发出：它参与了签名，
/// 客户端换个值发出去就会收到签名不符。不给这一项时 URL 不锁 Content-Type。
pub fn Client::presigned_put_url(
  self : Client,
  bucket : String,
  key : String,
  expires_sec~ : Int64 = 600L,
  content_type~ : String = "",
) -> String raise @error.OssError {
  self.presigned_url("PUT", bucket, key~, expires_sec~, content_type~)
}

///|
/// 本文件唯一读时钟的那一处。要钉住某个时刻就直接调 `@auth.presign_v4`——
/// 时钟进签名是 auth 那层的能力，不该在业务面重做一遍。
fn Client::presigned_url(
  self : Client,
  verb : String,
  bucket : String,
  key~ : String = "",
  expires_sec~ : Int64 = 600L,
  content_type~ : String = "",
) -> String raise @error.OssError {
  let config = self.config
  let timestamp = @auth.iso8601_basic(@auth.now_millis())
  let headers : Array[(String, String)] = if content_type.is_empty() {
    []
  } else {
    [("content-type", content_type)]
  }
  let signed = config
    .credentials()
    .presign_at(config.region_of(), timestamp, expires_sec, @auth.RequestToSign::{
      verb,
      canonical_uri: config.canonical_uri_of(bucket, key~),
      query: [],
      headers,
    })
  config.url_of(bucket, key~) + "?" + signed.query
}
