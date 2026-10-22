///|
test "post policy expiration is ISO8601 UTC with millis" {
  let value = post_policy_expiration(0L) catch {
    _ => abort("epoch zero must format")
  }
  assert_eq(value, "1970-01-01T00:00:00.000Z")
}

///|
test "post policy carries key, content type, metadata and status conditions" {
  let document = post_policy_document(
    bucket="b",
    key="a&b",
    content_type="text/plain",
    metadata=[("m", "v")],
    acl="",
    storage_class="",
    success_action_status=201,
    millis=0L,
    signature_version="v1",
    timestamp="",
    credential="",
  ) catch {
    _ => abort("policy must build")
  }
  assert_true(document.contains("\"expiration\":\"1970-01-01T00:00:00.000Z\""))
  assert_true(document.contains("[\"eq\",\"$key\",\"a&b\"]"))
  assert_true(document.contains("[\"eq\",\"$bucket\",\"b\"]"))
  assert_true(document.contains("[\"eq\",\"$Content-Type\",\"text/plain\"]"))
  assert_true(document.contains("[\"eq\",\"$x-oss-meta-m\",\"v\"]"))
  assert_true(document.contains("[\"eq\",\"$success_action_status\",\"201\"]"))
}

///|
test "post policy v4 carries credential, date and signature-version conditions" {
  let document = post_policy_document(
    bucket="b",
    key="a.txt",
    content_type="",
    metadata=[],
    acl="",
    storage_class="",
    success_action_status=204,
    millis=0L,
    signature_version="v4",
    timestamp="20261022T120000Z",
    credential="ak/20261022/cn-hangzhou/oss/aliyun_v4_request",
  ) catch {
    _ => abort("v4 policy must build")
  }
  assert_true(
    document.contains(
      "[\"eq\",\"$x-oss-signature-version\",\"OSS4-HMAC-SHA256\"]",
    ),
  )
  assert_true(
    document.contains(
      "[\"eq\",\"$x-oss-credential\",\"ak/20261022/cn-hangzhou/oss/aliyun_v4_request\"]",
    ),
  )
  assert_true(
    document.contains("[\"eq\",\"$x-oss-date\",\"20261022T120000Z\"]"),
  )
}

///|
test "post form puts the file last and keeps field values" {
  let body = post_form_body(
    "B",
    [("key", "k"), ("policy", "p")],
    @utf8.encode("abc".view()),
    "text/plain",
    "f.txt",
  )
  let text = @utf8.decode_lossy(body)
  assert_true(text.contains("name=\"key\"\r\n\r\nk\r\n"))
  assert_true(text.contains("name=\"policy\"\r\n\r\np\r\n"))
  assert_true(text.contains("name=\"file\"; filename=\"f.txt\""))
  assert_true(text.contains("Content-Type: text/plain\r\n\r\nabc\r\n"))
  assert_true(text.contains("--B--\r\n"))
}

///|
test "post policy signature matches a fixed V1 vector" {
  let credentials = @auth.Credentials::new("ak", "secret-key-example") catch {
    _ => abort("credentials must build")
  }
  let signature = credentials.post_policy_signature(
    "eyJleHBpcmF0aW9uIjoiMjAyNi0xMC0yMlQxNTowMDowMC4wMDBaIiwiY29uZGl0aW9ucyI6W119",
  )
  assert_eq(signature, "AWOQi7idArNrOpIDApTSeIDIgWo=")
}

///|
test "post form values reject CRLF" {
  let mut rejected = false
  reject_crlf("key", "a\rb") catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "filename helpers strip path and unsafe characters" {
  assert_eq(safe_filename("a/b.txt"), "b.txt")
  assert_eq(sanitize_filename("a\"b\\c"), "a_b_c")
  assert_eq(sanitize_filename(""), "object")
}
