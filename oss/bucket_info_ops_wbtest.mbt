///|
test "bucket info parse reads region, storage class and owner" {
  let body = "<BucketInfo><Bucket>" +
    "<Location>oss-cn-hangzhou</Location>" +
    "<StorageClass>Standard</StorageClass>" +
    "<CreationDate>2026-10-22T00:00:00.000Z</CreationDate>" +
    "<Owner><ID>1234</ID></Owner></Bucket></BucketInfo>"
  let info = bucket_info_of(body)
  assert_eq(info.region, Some("oss-cn-hangzhou"))
  assert_eq(info.storage_class, Some("Standard"))
  assert_eq(info.creation_date, Some("2026-10-22T00:00:00.000Z"))
  assert_eq(info.owner_id, Some("1234"))
}

///|
test "request payment document writes the payer" {
  assert_eq(
    payment_document("Requester"),
    "<RequestPaymentConfiguration><Payer>Requester</Payer></RequestPaymentConfiguration>",
  )
}
