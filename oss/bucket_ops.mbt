///|
/// 服务级与桶级列举两条。

///|
pub(all) struct BucketListing {
  names : Array[String]
  /// 回包原文。解析件只取简单形状，读不出的形状要能回查
  body : String
}

///|
/// 服务级 `GET /`：列这把凭据名下的桶。空桶名走的就是这条（`host_of("")` 不给桶前缀）。
pub async fn Client::list_buckets(
  self : Client,
) -> BucketListing raise @error.OssError {
  let response = request(self, "GET", "")
  let body = response_body_text(response.body, response.status)
  BucketListing::{ names: xml_all(body, "Name"), body, }
}

///|
/// 桶级列举走 ListObjects V2（`list-type=2`）：V1 的续页符是"上一页最后一个键"，
/// V2 给的是服务端自己发的 `NextContinuationToken`，翻页语义不用客户端猜。
///
/// `list-type`／`max-keys`／`prefix`／`delimiter`／`continuation-token` 全部进签名串——
/// 这一条正是待实测项第 1 条的读数处：真端点不认这种入签方式的话，这里当场
/// `SignatureDoesNotMatch`，不会静默通过。
///
/// 一行对象要同时读 `Key`／`Size`／`ETag`／`LastModified`，所以按 `<Contents>` **切段**
/// 再段内取值。把 `xml_all("Key")` 与 `xml_all("Size")` 各取一次再按下标配，
/// 遇到某个字段缺失的回包就会整体错位。
pub async fn Client::list_objects(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  delimiter~ : String = "",
  max_keys~ : Int32 = 100,
  continuation_token~ : String? = None,
) -> ObjectListing raise @error.OssError {
  let query : Array[(String, String)] = [
    ("list-type", "2"),
    ("max-keys", max_keys.to_string()),
  ]
  add_param(query, "prefix", prefix)
  add_param(query, "delimiter", delimiter)
  match continuation_token {
    Some(token) => query.push(("continuation-token", token))
    None => ()
  }
  let response = request(self, "GET", bucket, query~)
  let body = response_body_text(response.body, response.status)
  let objects : Array[ObjectInfo] = []
  for section in xml_sections(body, "Contents") {
    objects.push(ObjectInfo::{
      key: or_empty(xml_first(section, "Key")),
      etag: xml_first(section, "ETag"),
      size: parse_int64(or_empty(xml_first(section, "Size"))),
      last_modified: xml_first(section, "LastModified"),
      storage_class: xml_first(section, "StorageClass"),
    })
  }
  // `<Prefix>` 在 ListBucketResult 里也出现一次（回显请求的 prefix），而 CommonPrefixes
  // 那族同样是 `<Prefix>`——不切段就会把回显的那一条当成一个"目录"。
  let prefixes : Array[String] = []
  for group in xml_sections(body, "CommonPrefixes") {
    prefixes.push(or_empty(xml_first(group, "Prefix")))
  }
  ObjectListing::{
    objects,
    common_prefixes: prefixes,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_continuation_token: xml_first(body, "NextContinuationToken"),
    body,
  }
}

///|
/// 建桶。账号级动作，`bucket` 由调用方给；`acl`/`storage_class` 为空就不发对应头。
/// 本方法不接 `moon-file-storage` 门面，误用代价由公开 API 名字自己承担。
pub async fn Client::create_bucket(
  self : Client,
  bucket : String,
  acl~ : String = "",
  storage_class~ : String = "",
) -> Unit raise @error.OssError {
  if bucket.is_empty() {
    raise @error.BadParam("create_bucket needs a bucket name")
  }
  let response = request(
    self,
    "PUT",
    bucket,
    extra_headers=bucket_admin_headers(acl~, storage_class~),
  )
  discard_body(response)
}

///|
pub async fn Client::delete_bucket(
  self : Client,
  bucket : String,
) -> Unit raise @error.OssError {
  if bucket.is_empty() {
    raise @error.BadParam("delete_bucket needs a bucket name")
  }
  let response = request(self, "DELETE", bucket)
  discard_body(response)
}

///|
/// 只读判断：2xx 为真，404 为假；其余错误原样抛，不把 403 读成"不存在"。
pub async fn Client::bucket_exists(
  self : Client,
  bucket : String,
) -> Bool raise @error.OssError {
  if bucket.is_empty() {
    raise @error.BadParam("bucket_exists needs a bucket name")
  }
  let response = request(self, "HEAD", bucket) catch {
    err =>
      match err {
        @error.OssError::Service(details) =>
          if details.status == 404 {
            return false
          } else {
            raise err
          }
        _ => raise err
      }
  }
  discard_body(response)
  true
}

///|
fn bucket_admin_headers(
  acl~ : String,
  storage_class~ : String,
) -> Array[(String, String)] {
  let headers : Array[(String, String)] = []
  if !acl.is_empty() {
    headers.push(("x-oss-acl", acl))
  }
  if !storage_class.is_empty() {
    headers.push(("x-oss-storage-class", storage_class))
  }
  headers
}

///|
/// 值为空的参数不进查询串：`prefix=""` 与"没有 prefix"在签名上是两件事（前者签出
/// `prefix=`，后者根本不入签），发错了会让签名与 URL 两处各错一半。
fn add_param(
  query : Array[(String, String)],
  name : String,
  value : String,
) -> Unit {
  if !value.is_empty() {
    query.push((name, value))
  }
}

///|
/// `0` 是"读不出"的哨兵而不是"大小是 0"：调用侧要真读数就看 `body`，
/// 这里不静默造一个像真值的默认值。
fn parse_int64(text : String) -> Int64 {
  @string.parse_int64(text.view(), base=10) catch {
    _ => 0L
  }
}
