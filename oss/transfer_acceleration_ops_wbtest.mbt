///|
test "transfer acceleration document writes the enabled flag" {
  assert_eq(
    acceleration_document(true),
    "<TransferAccelerationConfiguration><Enabled>true</Enabled></TransferAccelerationConfiguration>",
  )
  assert_eq(
    acceleration_document(false),
    "<TransferAccelerationConfiguration><Enabled>false</Enabled></TransferAccelerationConfiguration>",
  )
}
