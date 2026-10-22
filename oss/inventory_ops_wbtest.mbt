///|
test "inventory document writes destination, schedule and fields" {
  let config = InventoryConfig::{
    id: "weekly",
    is_enabled: true,
    format: "CSV",
    destination_bucket: "report-bucket",
    destination_prefix: "reports/",
    account_id: "1234",
    role_arn: "acs:ram::1234:role/aliyunoss",
    frequency: "Weekly",
    included_versions: "All",
    filter_prefix: "logs/",
    optional_fields: ["Size", "ETag"],
  }
  assert_eq(
    inventory_document(config),
    "<InventoryConfiguration><Id>weekly</Id><IsEnabled>true</IsEnabled>" +
    "<Destination><OSSBucketDestination><Format>CSV</Format><AccountId>1234</AccountId>" +
    "<RoleArn>acs:ram::1234:role/aliyunoss</RoleArn><Bucket>report-bucket</Bucket>" +
    "<Prefix>reports/</Prefix></OSSBucketDestination></Destination>" +
    "<Schedule><Frequency>Weekly</Frequency></Schedule>" +
    "<Filter><Prefix>logs/</Prefix></Filter>" +
    "<IncludedObjectVersions>All</IncludedObjectVersions>" +
    "<OptionalFields><Field>Size</Field><Field>ETag</Field></OptionalFields>" +
    "</InventoryConfiguration>",
  )
}

///|
test "inventory parse reads a nested configuration" {
  let body = "<InventoryConfiguration><Id>weekly</Id><IsEnabled>false</IsEnabled>" +
    "<Destination><OSSBucketDestination><Format>CSV</Format><Bucket>dst</Bucket>" +
    "<Prefix>p/</Prefix></OSSBucketDestination></Destination>" +
    "<Schedule><Frequency>Daily</Frequency></Schedule>" +
    "<IncludedObjectVersions>Current</IncludedObjectVersions>" +
    "<OptionalFields><Field>Size</Field></OptionalFields></InventoryConfiguration>"
  let config = parse_inventory(body)
  assert_eq(config.id, "weekly")
  assert_eq(config.is_enabled, false)
  assert_eq(config.destination_bucket, "dst")
  assert_eq(config.destination_prefix, "p/")
  assert_eq(config.frequency, "Daily")
  assert_eq(config.optional_fields, ["Size"])
}

///|
test "inventory list parse splits configurations" {
  let body = "<ListInventoryConfigurationsResult>" +
    "<InventoryConfiguration><Id>a</Id><IsEnabled>true</IsEnabled></InventoryConfiguration>" +
    "<InventoryConfiguration><Id>b</Id><IsEnabled>false</IsEnabled></InventoryConfiguration>" +
    "</ListInventoryConfigurationsResult>"
  let configs = parse_inventories(body)
  assert_eq(configs.length(), 2)
  assert_eq(configs[0].id, "a")
  assert_eq(configs[1].is_enabled, false)
}
