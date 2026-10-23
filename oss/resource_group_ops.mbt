///|
/// 资源组：`GET/PUT /?resourceGroup`（官方 Go V2 `api_op_bucket_resourcegroup.go`，
/// 2026-10-22 现读）。只读写一个 `ResourceGroupId`；未配置时读口常见 404，落成 `None`。
pub async fn Client::get_bucket_resource_group(
  self : Client,
  bucket : String,
) -> String? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("resourceGroup", "")]) catch {
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
  let body = response_body_text(response.body, response.status)
  xml_first(body, "ResourceGroupId")
}

///|
pub async fn Client::put_bucket_resource_group(
  self : Client,
  bucket : String,
  resource_group_id : String,
) -> Unit raise @error.OssError {
  if resource_group_id.is_empty() {
    raise @error.BadParam("put_bucket_resource_group needs a resource group id")
  }
  let document = resource_group_document(resource_group_id)
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("resourceGroup", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
fn resource_group_document(resource_group_id : String) -> String {
  "<BucketResourceGroupConfiguration><ResourceGroupId>" +
  xml_escape(resource_group_id) +
  "</ResourceGroupId></BucketResourceGroupConfiguration>"
}
