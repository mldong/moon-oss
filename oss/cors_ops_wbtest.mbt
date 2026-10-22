///|
fn has_value(values : Array[String], want : String) -> Bool {
  for value in values {
    if value == want {
      return true
    }
  }
  false
}

///|
test "cors document and parser round-trip" {
  let rules = [
    CorsRule::{
      allowed_origins: ["https://a.example"],
      allowed_methods: ["GET", "PUT"],
      allowed_headers: ["*"],
      expose_headers: ["ETag"],
      max_age_seconds: Some(600),
    },
  ]
  let document = cors_document(rules)
  assert_true(
    document.contains("<AllowedOrigin>https://a.example</AllowedOrigin>"),
  )
  assert_true(document.contains("<MaxAgeSeconds>600</MaxAgeSeconds>"))
  let parsed = parse_cors_rules(document)
  assert_eq(parsed.length(), 1)
  assert_true(has_value(parsed[0].allowed_methods, "PUT"))
  assert_eq(parsed[0].max_age_seconds, Some(600))
}

///|
test "cors rejects a rule without origin or method" {
  let mut rejected = false
  check_cors_rules([
    CorsRule::{
      allowed_origins: [],
      allowed_methods: ["GET"],
      allowed_headers: [],
      expose_headers: [],
      max_age_seconds: None,
    },
  ]) catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
