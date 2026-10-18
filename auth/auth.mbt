///|
/// 一对 OSS 凭据。字段**不加** `pub(all)`：`secret_key` 一旦能被外面读到，
/// 一个"打印出来看看"的调试语句或一条 `derive(Show)` 就把它送进日志了。
pub struct Credentials {
  access_key : String
  secret_key : String
}

///|
/// 两把键任一为空就地拒——带着空键发出的请求只会在服务端变成一条看不出根因的 403。
pub fn Credentials::new(
  access_key : String,
  secret_key : String,
) -> Credentials raise @error.OssError {
  if access_key.is_empty() {
    raise @error.BadParam("access key is empty")
  }
  if secret_key.is_empty() {
    raise @error.BadParam("secret key is empty")
  }
  Credentials::{ access_key, secret_key, }
}

///|
/// 公开的那半把键（错误文案与记账要带它，签名本身不外露密钥）。
pub fn Credentials::access_key(self : Credentials) -> String {
  self.access_key
}

///|
/// 用当前 UTC 时刻签一次请求（真请求走这条）。`millis` 由调用方给，
/// 这样"注入时钟"这条路在 SDK 外面也是通的——测试与业务侧回放都靠它。
pub fn Credentials::sign_at(
  self : Credentials,
  region : String,
  millis : Int64,
  request : RequestToSign,
) -> Signature raise @error.OssError {
  let timestamp = iso8601_basic(millis)
  sign_v4(self.access_key, self.secret_key, region, timestamp, request)
}

///|
/// 头名与值的固定两件套：V4 必带的 `x-oss-date` 与 `x-oss-content-sha256`。
/// 值 `UNSIGNED-PAYLOAD` 是官方文档现读的唯一支持值——正文哈希不参与签名。
pub fn required_headers(timestamp : String) -> Array[(String, String)] {
  [("x-oss-date", timestamp), ("x-oss-content-sha256", unsigned_payload)]
}

///|
/// 本 SDK 读墙上时钟的**唯一一处**。要注入时钟（测试、回放）走
/// `Credentials::sign_at`，不要在这里改。
pub fn now_millis() -> Int64 {
  @date.now_millis()
}

///|
/// 用当前时刻签（真请求走这条）。
pub fn Credentials::sign_now(
  self : Credentials,
  region : String,
  request : RequestToSign,
) -> Signature raise @error.OssError {
  self.sign_at(region, @date.now_millis(), request)
}
