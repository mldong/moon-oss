///|
/// 桶防盗链：`GET/PUT /?referer`。官方 Go V2 的 `RefererConfiguration`
/// （`api_op_bucket_referer.go`，2026-10-22 现读）就六个字段：允许空 Referer、
/// 匹配时是否截掉查询串/路径、白名单、黑名单。OSS 没有独立的 delete 口：
/// 传空名单的 PUT 就是清空白名单，本仓照这一档。
pub(all) struct BucketReferer {
  allow_empty_referer : Bool?
  allow_truncate_query_string : Bool?
  truncate_path : Bool?
  referers : Array[String]
  blacklist : Array[String]
}

///|
pub async fn Client::put_bucket_referer(
  self : Client,
  bucket : String,
  config : BucketReferer,
) -> Unit raise @error.OssError {
  let document = referer_document(config)
  let response = request(
    self,
    "PUT",
    bucket,
    query=[("referer", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
/// 未配置防盗链时 OSS 回一份空白的 `RefererConfiguration`（不是 404）；
/// 读不到名单就是空数组，与官方 `RefererList` 的缺省同形。
pub async fn Client::get_bucket_referer(
  self : Client,
  bucket : String,
) -> BucketReferer raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("referer", "")])
  let body = response_body_text(response.body, response.status)
  parse_referer(body)
}

///|
fn referer_document(config : BucketReferer) -> String {
  let mut out = "<RefererConfiguration>"
  match config.allow_empty_referer {
    Some(flag) =>
      out = out +
        "<AllowEmptyReferer>" +
        flag.to_string() +
        "</AllowEmptyReferer>"
    None => ()
  }
  match config.allow_truncate_query_string {
    Some(flag) =>
      out = out +
        "<AllowTruncateQueryString>" +
        flag.to_string() +
        "</AllowTruncateQueryString>"
    None => ()
  }
  match config.truncate_path {
    Some(flag) =>
      out = out + "<TruncatePath>" + flag.to_string() + "</TruncatePath>"
    None => ()
  }
  out = out + "<RefererList>"
  for referer in config.referers {
    out = out + "<Referer>" + xml_escape(referer) + "</Referer>"
  }
  out = out + "</RefererList>"
  if !config.blacklist.is_empty() {
    out = out + "<RefererBlacklist>"
    for referer in config.blacklist {
      out = out + "<Referer>" + xml_escape(referer) + "</Referer>"
    }
    out = out + "</RefererBlacklist>"
  }
  out + "</RefererConfiguration>"
}

///|
fn parse_referer(body : String) -> BucketReferer {
  BucketReferer::{
    allow_empty_referer: parse_optional_bool(
      xml_first(body, "AllowEmptyReferer"),
    ),
    allow_truncate_query_string: parse_optional_bool(
      xml_first(body, "AllowTruncateQueryString"),
    ),
    truncate_path: parse_optional_bool(xml_first(body, "TruncatePath")),
    referers: referers_in(body, "RefererList"),
    blacklist: referers_in(body, "RefererBlacklist"),
  }
}

///|
fn referers_in(body : String, container : String) -> Array[String] {
  match xml_section_of(body, container) {
    None => []
    Some(section) => xml_all(section, "Referer")
  }
}
