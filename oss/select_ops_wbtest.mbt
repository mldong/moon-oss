///|
test "select document base64-encodes expression and delimiters" {
  assert_eq(
    select_csv_document(
      "SELECT * FROM object",
      record_delimiter="\n",
      field_delimiter=",",
    ),
    "<SelectRequest><Expression>U0VMRUNUICogRlJPTSBvYmplY3Q=</Expression>" +
    "<InputSerialization><CSV><RecordDelimiter>Cg==</RecordDelimiter>" +
    "<FieldDelimiter>LA==</FieldDelimiter></CSV></InputSerialization>" +
    "<OutputSerialization><CSV><RecordDelimiter>Cg==</RecordDelimiter></CSV>" +
    "</OutputSerialization></SelectRequest>",
  )
}
