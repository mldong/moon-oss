///|
test "replication document writes destination and history flags" {
  let rule = ReplicationRule::new("repl-1", "backup-bucket", prefix="logs/")
  let config = ReplicationConfig::{ rules: [rule], }
  assert_eq(
    replication_document(config),
    "<ReplicationConfiguration><Rule><ID>repl-1</ID><Prefix>logs/</Prefix>" +
    "<Status>Enabled</Status><Destination><Bucket>backup-bucket</Bucket></Destination>" +
    "<HistoricalObjectReplication>Disabled</HistoricalObjectReplication></Rule>" +
    "</ReplicationConfiguration>",
  )
}

///|
test "replication parse reads rules and destination fields" {
  let body = "<ReplicationConfiguration><Rule><ID>a</ID><Prefix>img/</Prefix>" +
    "<Status>Enabled</Status><Destination><Bucket>dst-a</Bucket><Location>oss-cn-beijing</Location>" +
    "<TransferType>internal</TransferType></Destination>" +
    "<HistoricalObjectReplication>Enabled</HistoricalObjectReplication></Rule>" +
    "<Rule><ID>b</ID><Prefix></Prefix><Status>Disabled</Status>" +
    "<Destination><Bucket>dst-b</Bucket></Destination></Rule></ReplicationConfiguration>"
  let config = parse_replication(body)
  assert_eq(config.rules.length(), 2)
  assert_eq(config.rules[0].destination_bucket, "dst-a")
  assert_eq(config.rules[0].destination_location, "oss-cn-beijing")
  assert_eq(config.rules[0].transfer_type, "internal")
  assert_eq(config.rules[0].historical_object_replication, "Enabled")
  assert_eq(config.rules[1].status, "Disabled")
}
