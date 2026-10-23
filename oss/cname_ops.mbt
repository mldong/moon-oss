///|
/// 自定义域（CNAME）：`POST /?cname&comp=add`、`GET /?cname`、
/// `POST /?cname&comp=delete`（官方 Go V2 `api_op_bucket_cname.go`，2026-10-22 现读）。
/// 增删都走同一个 XML 根 `BucketCnameConfiguration`；本版只覆盖域名本身，
/// 证书与 token 校验那两族不在这批。
pub(all) struct CnameInfo {
  domain : String
  status : String
  last_modified : String
}

///|
pub async fn Client::put_bucket_cname(
  self : Client,
  bucket : String,
  domain : String,
) -> Unit raise @error.OssError {
  if domain.is_empty() {
    raise @error.BadParam("put_bucket_cname needs a domain")
  }
  let document = cname_document(domain)
  let response = request(
    self,
    "POST",
    bucket,
    query=[("cname", ""), ("comp", "add")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::list_bucket_cnames(
  self : Client,
  bucket : String,
) -> Array[CnameInfo] raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("cname", "")])
  let body = response_body_text(response.body, response.status)
  parse_cnames(body)
}

///|
pub async fn Client::delete_bucket_cname(
  self : Client,
  bucket : String,
  domain : String,
) -> Unit raise @error.OssError {
  if domain.is_empty() {
    raise @error.BadParam("delete_bucket_cname needs a domain")
  }
  let document = cname_document(domain)
  let response = request(
    self,
    "POST",
    bucket,
    query=[("cname", ""), ("comp", "delete")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
fn cname_document(domain : String) -> String {
  "<BucketCnameConfiguration><Cname><Domain>" +
  xml_escape(domain) +
  "</Domain></Cname></BucketCnameConfiguration>"
}

///|
fn parse_cnames(body : String) -> Array[CnameInfo] {
  let out : Array[CnameInfo] = []
  for section in xml_sections(body, "Cname") {
    out.push(CnameInfo::{
      domain: xml_first(section, "Domain").unwrap_or(""),
      status: xml_first(section, "Status").unwrap_or(""),
      last_modified: xml_first(section, "LastModified").unwrap_or(""),
    })
  }
  out
}
