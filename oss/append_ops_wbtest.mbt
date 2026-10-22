///|
test "append query and next-position header" {
  let query = append_query(5L)
  assert_eq(query[0].0, "append")
  assert_eq(query[0].1, "")
  assert_eq(query[1].0, "position")
  assert_eq(query[1].1, "5")
  let headers = [
    @transport.Header::{ name: "x-oss-next-append-position", value: "5", },
  ]
  assert_eq(header_int64(headers, "x-oss-next-append-position"), Some(5L))
}
