///|
fn has_status(status : String) -> Bool {
  status == "Enabled" || status == "Suspended"
}

///|
test "versioning accepts the two official statuses" {
  assert_true(has_status("Enabled"))
  assert_true(has_status("Suspended"))
  assert_true(!has_status("enabled"))
}

///|
test "versioning rejects unknown status" {
  let mut rejected = false
  check_versioning_status("On") catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
