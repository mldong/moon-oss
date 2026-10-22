///|
test "lifecycle document writes the official element order" {
  let rules = [
    LifecycleRule::new("expire-logs", prefix="logs/")
    .with_expiration(days=Some(30))
    .with_transitions([
      LifecycleTransition::{ days: Some(7), date: None, storage_class: "IA", },
    ])
    .with_abort_multipart(3),
  ]
  assert_eq(
    lifecycle_document(rules),
    "<LifecycleConfiguration><Rule><ID>expire-logs</ID><Prefix>logs/</Prefix>" +
    "<Status>Enabled</Status><Expiration><Days>30</Days></Expiration>" +
    "<Transition><Days>7</Days><StorageClass>IA</StorageClass></Transition>" +
    "<AbortMultipartUpload><Days>3</Days></AbortMultipartUpload></Rule></LifecycleConfiguration>",
  )
}

///|
test "lifecycle parse reads expiration, transition and noncurrent days" {
  let sample = "<LifecycleConfiguration><Rule><ID>a</ID><Prefix></Prefix><Status>Enabled</Status>" +
    "<Expiration><Days>10</Days><ExpiredObjectDeleteMarker>false</ExpiredObjectDeleteMarker></Expiration>" +
    "<Transition><Days>5</Days><StorageClass>Archive</StorageClass></Transition>" +
    "<NoncurrentVersionExpiration><NoncurrentDays>20</NoncurrentDays></NoncurrentVersionExpiration>" +
    "</Rule><Rule><ID>b</ID><Prefix>tmp/</Prefix><Status>Disabled</Status>" +
    "<Expiration><Date>2027-01-01T00:00:00.000Z</Date></Expiration></Rule></LifecycleConfiguration>"
  let rules = parse_lifecycle_rules(sample)
  assert_eq(rules.length(), 2)
  assert_eq(rules[0].id, "a")
  assert_eq(rules[0].expiration_days, Some(10))
  assert_eq(rules[0].expired_object_delete_marker, Some(false))
  assert_eq(rules[0].transitions.length(), 1)
  assert_eq(rules[0].transitions[0].storage_class, "Archive")
  assert_eq(rules[0].noncurrent_version_expiration_days, Some(20))
  assert_eq(rules[1].status, "Disabled")
  assert_eq(rules[1].expiration_date, Some("2027-01-01T00:00:00.000Z"))
  assert_eq(rules[1].transitions.length(), 0)
}

///|
test "lifecycle parse survives an empty configuration" {
  assert_eq(
    parse_lifecycle_rules("<LifecycleConfiguration></LifecycleConfiguration>").length(),
    0,
  )
  assert_eq(parse_lifecycle_rules("").length(), 0)
}
