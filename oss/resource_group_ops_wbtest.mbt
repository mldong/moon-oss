///|
test "resource group document writes the id" {
  assert_eq(
    resource_group_document("rg-1234"),
    "<BucketResourceGroupConfiguration><ResourceGroupId>rg-1234</ResourceGroupId>" +
    "</BucketResourceGroupConfiguration>",
  )
}
