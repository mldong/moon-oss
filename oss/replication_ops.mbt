///|
/// 桶复制：`GET /?replication`、`POST /?comp=add&replication`、`POST /?comp=delete&replication`
/// （官方 Go V2 `api_op_bucket_replication.go:232-452`，2026-10-22 现读）。
/// 本版覆盖规则 ID／前缀／状态／目标桶与地域／传输类型／历史对象复制；
/// RTC、KMS、进度与源端选择条件不在这一版。
pub(all) struct ReplicationRule {
  id : String
  prefix : String
  status : String
  destination_bucket : String
  destination_location : String
  transfer_type : String
  historical_object_replication : String
}

///|
pub(all) struct ReplicationConfig {
  rules : Array[ReplicationRule]
}

///|
pub fn ReplicationRule::new(
  id : String,
  destination_bucket : String,
  status~ : String = "Enabled",
  prefix~ : String = "",
) -> ReplicationRule {
  ReplicationRule::{
    id,
    prefix,
    status,
    destination_bucket,
    destination_location: "",
    transfer_type: "",
    historical_object_replication: "Disabled",
  }
}

///|
pub async fn Client::put_bucket_replication(
  self : Client,
  bucket : String,
  config : ReplicationConfig,
) -> Unit raise @error.OssError {
  if config.rules.is_empty() {
    raise @error.BadParam("put_bucket_replication needs at least one rule")
  }
  for rule in config.rules {
    if rule.destination_bucket.is_empty() {
      raise @error.BadParam(
        "replication rule without a destination bucket: " + rule.id,
      )
    }
    if rule.status != "Enabled" && rule.status != "Disabled" {
      raise @error.BadParam(
        "replication rule status must be Enabled or Disabled, got " +
        rule.status,
      )
    }
  }
  let document = replication_document(config)
  let response = request(
    self,
    "POST",
    bucket,
    query=[("comp", "add"), ("replication", "")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
/// 未配置时 OSS 回 404；这一档落成 `None`。
pub async fn Client::get_bucket_replication(
  self : Client,
  bucket : String,
) -> ReplicationConfig? raise @error.OssError {
  let response = request(self, "GET", bucket, query=[("replication", "")]) catch {
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
  Some(parse_replication(body))
}

///|
pub async fn Client::delete_bucket_replication(
  self : Client,
  bucket : String,
) -> Unit raise @error.OssError {
  let response = request(self, "POST", bucket, query=[
    ("comp", "delete"),
    ("replication", ""),
  ])
  discard_body(response)
}

///|
fn replication_document(config : ReplicationConfig) -> String {
  let mut out = "<ReplicationConfiguration>"
  for rule in config.rules {
    out = out + "<Rule><ID>" + xml_escape(rule.id) + "</ID>"
    out = out + "<Prefix>" + xml_escape(rule.prefix) + "</Prefix>"
    out = out + "<Status>" + xml_escape(rule.status) + "</Status>"
    out = out +
      "<Destination><Bucket>" +
      xml_escape(rule.destination_bucket) +
      "</Bucket>"
    if !rule.destination_location.is_empty() {
      out = out +
        "<Location>" +
        xml_escape(rule.destination_location) +
        "</Location>"
    }
    if !rule.transfer_type.is_empty() {
      out = out +
        "<TransferType>" +
        xml_escape(rule.transfer_type) +
        "</TransferType>"
    }
    out = out + "</Destination>"
    if !rule.historical_object_replication.is_empty() {
      out = out +
        "<HistoricalObjectReplication>" +
        xml_escape(rule.historical_object_replication) +
        "</HistoricalObjectReplication>"
    }
    out = out + "</Rule>"
  }
  out + "</ReplicationConfiguration>"
}

///|
fn parse_replication(body : String) -> ReplicationConfig {
  let rules : Array[ReplicationRule] = []
  for section in xml_sections(body, "Rule") {
    let destination = match xml_section_of(section, "Destination") {
      Some(text) => text
      None => ""
    }
    rules.push(ReplicationRule::{
      id: xml_first(section, "ID").unwrap_or(""),
      prefix: xml_first(section, "Prefix").unwrap_or(""),
      status: xml_first(section, "Status").unwrap_or(""),
      destination_bucket: xml_first(destination, "Bucket").unwrap_or(""),
      destination_location: xml_first(destination, "Location").unwrap_or(""),
      transfer_type: xml_first(destination, "TransferType").unwrap_or(""),
      historical_object_replication: xml_first(
        section, "HistoricalObjectReplication",
      ).unwrap_or(""),
    })
  }
  ReplicationConfig::{ rules, }
}
