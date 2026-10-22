///|
/// 批量删除。OSS 的 `DeleteMultipleObjects` 走 `POST /?delete`，请求体是 XML，
/// 且 `Content-MD5` 是必带头——这一格不能省，服务端会直接拒。
///
/// 上限按官方文档在本地先拒（1000 个键）；空键也先拒，不把明显不合法的输入
/// 发出去换一条 `MalformedXML`。`quiet=true` 时服务端可以不回正文，读数为空数组。
pub async fn Client::delete_objects(
  self : Client,
  bucket : String,
  keys : Array[String],
  quiet~ : Bool = false,
) -> DeleteObjectsResult raise @error.OssError {
  if keys.is_empty() {
    raise @error.BadParam("delete_objects needs at least one key")
  }
  if keys.length() > 1000 {
    raise @error.BadParam(
      "delete_objects accepts at most 1000 keys per request, got " +
      keys.length().to_string(),
    )
  }
  for key in keys {
    if key.is_empty() {
      raise @error.BadParam("delete_objects key must not be empty")
    }
  }
  let document = delete_objects_document(keys, quiet)
  let body = @utf8.encode(document.view())
  let content_md5 = content_md5_of(body)
  let response = request(
    self,
    "POST",
    bucket,
    query=[("delete", "")],
    extra_headers=[
      ("content-type", "application/xml"),
      ("content-md5", content_md5),
    ],
    body=@transport.RequestBody::Bytes(body),
  )
  let text = response_body_text(response.body, response.status)
  parse_delete_objects_result(text)
}

///|
/// 请求体只带官方文档里这一轮承诺的两格：`Quiet` 与 `Object/Key`。
/// `VersionId` 属于版本控制面，等那条腿落地再加，不在这里预占一个“看起来支持”的字段。
fn delete_objects_document(keys : Array[String], quiet : Bool) -> String {
  let mut out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Delete>"
  if quiet {
    out = out + "<Quiet>true</Quiet>"
  }
  for key in keys {
    out = out + "<Object><Key>" + xml_escape(key) + "</Key></Object>"
  }
  out + "</Delete>"
}

///|
/// 成功与失败是 `<DeleteResult>` 下两类兄弟节点。按 `Deleted`/`Error` 分段读，
/// 不拿两棵 `Key` 列表各扫一遍——长度不等时那种读法会把上一段的键接到下一段上。
fn parse_delete_objects_result(body : String) -> DeleteObjectsResult {
  let deleted : Array[String] = []
  for section in xml_sections(body, "Deleted") {
    match xml_first(section, "Key") {
      Some(key) => deleted.push(key)
      None => ()
    }
  }
  let errors : Array[DeleteObjectFailure] = []
  for section in xml_sections(body, "Error") {
    errors.push(DeleteObjectFailure::{
      key: or_empty(xml_first(section, "Key")),
      code: or_empty(xml_first(section, "Code")),
      message: or_empty(xml_first(section, "Message")),
    })
  }
  DeleteObjectsResult::{ deleted, errors, body, }
}
