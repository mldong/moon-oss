///|
/// **V4 查询串签名**（预签名 URL）。与 Header 签名同一条规范化链，只差三处：
/// 凭据／时刻／有效期这三样从头部搬到查询参数里，`x-oss-signature` 最后才加所以不入签，
/// 以及**不带** `x-oss-content-sha256`（生成 URL 时无法预知实际传输的正文）。

///|
pub(all) struct PresignedUrl {
  /// 已排序、已编码的查询串（含 `x-oss-signature`），直接拼在 `scheme://host/path?` 之后
  query : String
  signature : String
  timestamp : String
  scope : String
  /// 参与签名的非必选头名；空串表示 URL 里不声明这一项
  additional_headers : String
}

///|
/// 有效期上限现读：永久密钥 7 天（604800 秒），STS 临时密钥 12 小时。
/// 这里按永久密钥那一档做界——超出一律 `BadParam`，而不是发出去等真端点回一条含糊的 403。
let presign_max_seconds : Int64 = 604800L

///|
pub fn presign_v4(
  access_key : String,
  secret_key : String,
  region : String,
  timestamp : String,
  expires : Int64,
  req : RequestToSign,
) -> PresignedUrl raise @error.OssError {
  if timestamp.length() < 15 {
    raise @error.BadParam(
      "timestamp must be YYYYMMDDTHHMMSSZ, got " + timestamp,
    )
  }
  if expires <= 0L || expires > presign_max_seconds {
    let limit = presign_max_seconds.to_string()
    raise @error.BadParam(
      "presign validity must be within 1.." +
      limit +
      " seconds, got " +
      expires.to_string(),
    )
  }
  let date = timestamp[0:8].to_owned()
  let scope = scope_of(date, region)
  let block = canonical_headers(req.headers)
  let extras = additional_headers(block.signed_names)
  let credential = access_key + "/" + scope
  let params : Array[(String, String)] = req.query +
    [
      ("x-oss-signature-version", "OSS4-HMAC-SHA256"),
      ("x-oss-credential", credential),
      ("x-oss-date", timestamp),
      ("x-oss-expires", expires.to_string()),
    ]
  if !extras.is_empty() {
    params.push(("x-oss-additional-headers", extras))
  }
  let with_credentials = RequestToSign::{
    verb: req.verb,
    canonical_uri: req.canonical_uri,
    query: params,
    headers: req.headers,
  }
  let canonical = canonical_request(with_credentials)
  let string_to_sign = string_to_sign_of(timestamp, scope, canonical)
  let signature = signature_of(secret_key, date, region, string_to_sign)
  PresignedUrl::{
    query: canonical_query_string(params) + "&x-oss-signature=" + signature,
    signature,
    timestamp,
    scope,
    additional_headers: extras,
  }
}
