///|
/// 桶 Policy：`GET/PUT/DELETE /?policy`。官方 Go V2 `api_op_bucket_policy.go`
/// （2026-10-22 现读）：body 是原始 JSON 文档，PUT 用 `application/json`；
/// 读口在未配置时回 404 `NoSuchBucketPolicy`，这一档落成 `None`。
pub async fn Client::put_bucket_policy(
  self : Client,
  bucket : String,
  policy : String,
) -> Unit raise @error.OssError {
  if policy.is_empty() {
    raise @error.BadParam("put_bucket_policy needs a non-empty policy document")
  }
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("policy", "")],
    extra_headers=[("content-type", "application/json")],
    body=@transport.RequestBody::Bytes(@utf8.encode(policy.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_policy(
  self : Client,
  bucket : String,
) -> String? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("policy", "")]) catch {
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
  Some(response_body_text(response.body, response.status))
}

///|
pub async fn Client::delete_bucket_policy(
  self : Client,
  bucket : String,
) -> Unit raise @error.OssError {
  let response = request(self, "DELETE", bucket, query=[("policy", "")])
  discard_body(response)
}
