///|
test "cname document wraps the domain" {
  assert_eq(
    cname_document("cdn.example.com"),
    "<BucketCnameConfiguration><Cname><Domain>cdn.example.com</Domain>" +
    "</Cname></BucketCnameConfiguration>",
  )
}

///|
test "cname list parse reads domains and status" {
  let body = "<ListCnameResult><Cname><Domain>a.example.com</Domain>" +
    "<Status>Enabled</Status><LastModified>2026-10-22T00:00:00.000Z</LastModified>" +
    "</Cname></ListCnameResult>"
  let items = parse_cnames(body)
  assert_eq(items.length(), 1)
  assert_eq(items[0].domain, "a.example.com")
  assert_eq(items[0].status, "Enabled")
}
