///|
/// 对象级 ACL 两条。OSS 用的是自己的两个 API 而非 S3 的 canned ACL：
/// 写侧 `PUT /<key>?acl` + 头 `x-oss-object-acl`，读侧 `GET /<key>?acl` 回
/// `AccessControlPolicy/AccessControlList/Grant`。
///
/// 这一族的价值有一半在**签名**上：`?acl` 是无值参数，规范化查询串里只写键名、不带 `=`
/// （与 SigV4 的 `acl=` 不同）。所以这一条同时也是待实测项第 1 条的读数处。

///|
pub(all) struct ObjectAcl {
  /// `<Grant>` 的读数：`private`／`public-read`／`public-read-write`
  grant : String
  owner_id : String?
  body : String
}

///|
pub async fn Client::put_object_acl(
  self : Client,
  bucket : String,
  key : String,
  acl : String,
) -> Unit raise @error.OssError {
  if acl.is_empty() {
    raise @error.BadParam("acl value is required")
  }
  let response = request(self, "PUT", bucket, key~, query=[("acl", "")], extra_headers=[
    ("x-oss-object-acl", acl),
  ])
  discard_body(response)
}

///|
pub async fn Client::get_object_acl(
  self : Client,
  bucket : String,
  key : String,
) -> ObjectAcl raise @error.OssError {
  let response = request(self, "GET", bucket, key~, query=[("acl", "")])
  let body = response_body_text(response.body, response.status)
  ObjectAcl::{
    grant: or_empty(xml_first(body, "Grant")),
    owner_id: xml_first(body, "ID"),
    body,
  }
}
