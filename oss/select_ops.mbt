///|
/// 对象内查询：`POST /<key>?x-oss-process=csv/select`，body 是
/// `SelectRequest` XML（`Expression` 按官方 SDK 做 Base64），应答是 **event-stream**
/// 帧（Records/Stats/End）。本版把原始字节交回调用方，帧解码留到下一层；
/// JSON 输入那一档（`json/select`）不在这版。
pub async fn Client::select_object_csv(
  self : Client,
  bucket : String,
  key : String,
  expression : String,
  record_delimiter~ : String = "\n",
  field_delimiter~ : String = ",",
) -> Bytes raise @error.OssError {
  if expression.is_empty() {
    raise @error.BadParam("select_object_csv needs an expression")
  }
  let document = select_csv_document(
    expression,
    record_delimiter~,
    field_delimiter~,
  )
  let response = request(
    self,
    "POST",
    bucket,
    key~,
    query=[("x-oss-process", "csv/select")],
    extra_headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  let raw = read_all(response.body)
  response.body.close()
  raw
}

///|
fn select_csv_document(
  expression : String,
  record_delimiter~ : String,
  field_delimiter~ : String,
) -> String {
  let encoded = @base64.encode(@utf8.encode(expression.view()).exact_view())
  let record_b64 = @base64.encode(
    @utf8.encode(record_delimiter.view()).exact_view(),
  )
  let field_b64 = @base64.encode(
    @utf8.encode(field_delimiter.view()).exact_view(),
  )
  "<SelectRequest><Expression>" +
  encoded +
  "</Expression><InputSerialization><CSV><RecordDelimiter>" +
  record_b64 +
  "</RecordDelimiter><FieldDelimiter>" +
  field_b64 +
  "</FieldDelimiter></CSV></InputSerialization><OutputSerialization><CSV>" +
  "<RecordDelimiter>" +
  record_b64 +
  "</RecordDelimiter></CSV></OutputSerialization></SelectRequest>"
}
