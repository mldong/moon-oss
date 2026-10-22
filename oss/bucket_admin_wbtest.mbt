///|
fn has_header(
  headers : Array[(String, String)],
  name : String,
  value : String,
) -> Bool {
  for pair in headers {
    if pair.0 == name && pair.1 == value {
      return true
    }
  }
  false
}

///|
test "bucket admin headers carry only non-empty options" {
  let headers = bucket_admin_headers(acl="private", storage_class="IA")
  assert_true(has_header(headers, "x-oss-acl", "private"))
  assert_true(has_header(headers, "x-oss-storage-class", "IA"))
  let empty = bucket_admin_headers(acl="", storage_class="")
  assert_eq(empty.length(), 0)
}
