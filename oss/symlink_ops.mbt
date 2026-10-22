///|
/// 软链接：`PUT/GET /<key>?symlink`。官方 Go V2 `PutSymlink`/`GetSymlink`
/// （`api_op_object.go:2174-2300`，2026-10-22 现读）：目标写在 `x-oss-symlink-target`
/// 头里，读侧也从同一个头回。链接对象不占数据体，删链接不删目标。
pub(all) struct SymlinkInfo {
  target : String?
  etag : String?
  version_id : String?
}

///|
pub async fn Client::put_symlink(
  self : Client,
  bucket : String,
  key : String,
  target : String,
  forbid_overwrite~ : Bool = false,
  storage_class~ : String = "",
  acl~ : String = "",
) -> Unit raise @error.OssError {
  if target.is_empty() {
    raise @error.BadParam("put_symlink needs a target key")
  }
  let response = request(
    self,
    "PUT",
    bucket,
    key~,
    query=[("symlink", "")],
    extra_headers=symlink_headers(
      target,
      forbid_overwrite~,
      storage_class~,
      acl~,
    ),
  )
  discard_body(response)
}

///|
pub async fn Client::get_symlink(
  self : Client,
  bucket : String,
  key : String,
) -> SymlinkInfo raise @error.OssError {
  let response = request(self, "GET", bucket, key~, query=[("symlink", "")])
  discard_body(response)
  SymlinkInfo::{
    target: header_of(response.headers, "x-oss-symlink-target"),
    etag: header_of(response.headers, "etag"),
    version_id: header_of(response.headers, "x-oss-version-id"),
  }
}

///|
pub fn symlink_headers(
  target : String,
  forbid_overwrite~ : Bool = false,
  storage_class~ : String = "",
  acl~ : String = "",
) -> Array[(String, String)] {
  let headers : Array[(String, String)] = [("x-oss-symlink-target", target)]
  if forbid_overwrite {
    headers.push(("x-oss-forbid-overwrite", "true"))
  }
  if !storage_class.is_empty() {
    headers.push(("x-oss-storage-class", storage_class))
  }
  if !acl.is_empty() {
    headers.push(("x-oss-object-acl", acl))
  }
  headers
}
