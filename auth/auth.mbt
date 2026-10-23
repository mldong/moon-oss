///|
/// 一对 OSS 凭据。字段**不加** `pub(all)`：`secret_key` 一旦能被外面读到，
/// 一个"打印出来看看"的调试语句或一条 `derive(Show)` 就把它送进日志了。
pub struct Credentials {
  access_key : String
  secret_key : String
  security_token : String?
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
  Credentials::{ access_key, secret_key, security_token: None, }
}

///|
/// 公开的那半把键（错误文案与记账要带它，签名本身不外露密钥）。
pub fn Credentials::access_key(self : Credentials) -> String {
  self.access_key
}

///|
/// 挂一把 STS 临时令牌；空串视作"不挂"，返回自身。
pub fn Credentials::with_security_token(
  self : Credentials,
  token : String,
) -> Credentials {
  if token.is_empty() {
    self
  } else {
    Credentials::{
      access_key: self.access_key,
      secret_key: self.secret_key,
      security_token: Some(token),
    }
  }
}

///|
pub fn Credentials::security_token(self : Credentials) -> String? {
  self.security_token
}

///|
/// POST Object 的 V1 表单签名：`Base64(HMAC-SHA1(secret, Base64(policy)))`。
/// 这是官方 PostObject 文档现读的 V1 形状；V4 表单签名（`x-oss-signature-version` 那一族）
/// 尚未落，调用方若要 V4 需等后续代次。
pub fn Credentials::post_policy_signature(
  self : Credentials,
  policy_base64 : String,
) -> String {
  @base64.encode(
    @digest.hmac_sha1_of_bytes(
      @utf8.encode(self.secret_key.view()),
      @utf8.encode(policy_base64.view()),
    ).exact_view(),
  )
}

///|
/// POST Object 的 V4 表单签名：`hex(HMAC(signing_key, Base64(policy)))`，
/// 密钥链与请求签名共用 [signing_key]（`aliyun_v4`+SK → date → region → oss →
/// `aliyun_v4_request`）。`date` 是 `YYYYMMDD`，与 policy 里的 `x-oss-credential` 同一段。
pub fn Credentials::post_policy_signature_v4(
  self : Credentials,
  policy_base64 : String,
  date : String,
  region : String,
) -> String {
  @digest.hmac_sha256_hex_of_bytes(
    signing_key(self.secret_key, date, region),
    @utf8.encode(policy_base64.view()),
  )
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
/// 用注入的时刻签一次**查询串**签名（预签名 URL 走这条）。密钥只在这一层被读到——
/// `Credentials` 的字段不公开，业务面拿不到 SK 也能出 URL。
pub fn Credentials::presign_at(
  self : Credentials,
  region : String,
  timestamp : String,
  expires : Int64,
  request : RequestToSign,
) -> PresignedUrl raise @error.OssError {
  presign_v4(
    self.access_key,
    self.secret_key,
    region,
    timestamp,
    expires,
    request,
  )
}
