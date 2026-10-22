///|
test "referer document writes whitelist and blacklist" {
  let config = BucketReferer::{
    allow_empty_referer: Some(false),
    allow_truncate_query_string: Some(true),
    truncate_path: None,
    referers: ["http://www.aliyun.com", "https://*.example.com"],
    blacklist: ["http://refuse.example"],
  }
  assert_eq(
    referer_document(config),
    "<RefererConfiguration><AllowEmptyReferer>false</AllowEmptyReferer>" +
    "<AllowTruncateQueryString>true</AllowTruncateQueryString><RefererList>" +
    "<Referer>http://www.aliyun.com</Referer><Referer>https://*.example.com</Referer>" +
    "</RefererList><RefererBlacklist><Referer>http://refuse.example</Referer>" +
    "</RefererBlacklist></RefererConfiguration>",
  )
}

///|
test "referer parse reads both lists and the three switches" {
  let body = "<RefererConfiguration><AllowEmptyReferer>true</AllowEmptyReferer>" +
    "<AllowTruncateQueryString>false</AllowTruncateQueryString><TruncatePath>true</TruncatePath>" +
    "<RefererList><Referer>*.a.example</Referer></RefererList>" +
    "<RefererBlacklist><Referer>*.b.example</Referer></RefererBlacklist>" +
    "</RefererConfiguration>"
  let config = parse_referer(body)
  assert_eq(config.allow_empty_referer, Some(true))
  assert_eq(config.allow_truncate_query_string, Some(false))
  assert_eq(config.truncate_path, Some(true))
  assert_eq(config.referers, ["*.a.example"])
  assert_eq(config.blacklist, ["*.b.example"])
}

///|
test "referer empty configuration parses to empty lists" {
  let config = parse_referer("<RefererConfiguration></RefererConfiguration>")
  assert_eq(config.allow_empty_referer, None)
  assert_eq(config.referers.length(), 0)
  assert_eq(config.blacklist.length(), 0)
  let cleared = BucketReferer::{
    allow_empty_referer: None,
    allow_truncate_query_string: None,
    truncate_path: None,
    referers: [],
    blacklist: [],
  }
  assert_eq(
    referer_document(cleared),
    "<RefererConfiguration><RefererList></RefererList></RefererConfiguration>",
  )
}
