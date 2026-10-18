///|
pub struct Client {
  config : @config.Config
  transport : &@transport.Transport
}

///|
/// 传输层是注入的（与 moon-s3／moon-kodo 同一套端口）：业务侧可以换成带连接池、
/// 带自定义超时的实现，测试侧可以塞假端点。
pub fn Client::new(
  config : @config.Config,
  transport : &@transport.Transport,
) -> Client {
  Client::{ config, transport, }
}

///|
pub(all) struct BucketListing {
  names : Array[String]
  /// 原始响应体。解析件只取简单形状，读不出的形状要能回查
  body : String
}

///|
/// 服务级 `GET /`：列这把凭据名下的桶。空桶名走的就是这条（`host_of("")` 不给桶前缀）。
pub async fn Client::list_buckets(
  self : Client,
) -> BucketListing raise @error.OssError {
  let response = request(self, "GET", "")
  let body = response_body_text(response.body, response.status)
  BucketListing::{ names: @error.xml_all(body, "Name"), body, }
}

///|
pub(all) struct ObjectListing {
  keys : Array[String]
  truncated : Bool
  /// 回包缺 `IsTruncated` 时是 false——与"确实没截断"同值，所以 `body` 一并留着供判读
  body : String
}

///|
/// 桶级列举，走 ListObjects V2（`list-type=2`）。`prefix` 与 `max-keys` 都进签名串，
/// 真端点若不接受这种入签方式，这一条会当场 `SignatureDoesNotMatch` 而不是静默通过。
pub async fn Client::list_objects(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  max_keys~ : Int32 = 100,
) -> ObjectListing raise @error.OssError {
  let query : Array[(String, String)] = [
    ("list-type", "2"),
    ("max-keys", max_keys.to_string()),
  ]
  let query = if prefix.is_empty() {
    query
  } else {
    query + [("prefix", prefix)]
  }
  let response = request(self, "GET", bucket, query~)
  let body = response_body_text(response.body, response.status)
  let truncated = or_empty(@error.xml_first(body, "IsTruncated")) == "true"
  ObjectListing::{ keys: @error.xml_all(body, "Key"), truncated, body, }
}
