///|
// 确定性向量：不联网，钉住"同一输入→同一规范化串→同一签名"。
// 真端点那一半在 live_test.mbt 里；两边都要在——只有向量测试会把"我算得自洽"当成"我对"，
// 只有真端点测试则查不出某一天的重构悄悄改了编码规则。
//
// 下面这一组期望值不是"跑一遍实现抄回来的读数"：规范化串按官方六行形状逐行手推，
// 签名值由一份独立实现（标准库 `hmac`/`hashlib`）算出。两份算法对得上，这条回归钉才有意义。

///|
/// 2026-10-18T06:41:24Z 的 epoch 毫秒。
/// 下面那条 ISO8601 用例同时钉住一件承重前提：签名要的是 UTC 读数，而 date 包对区名是
/// "查不到就 `None`"（不是回落到某个默认区）——区名一旦拼错，这里会当场报错，
/// 不会静默偏 8 小时签出一个形状完全合法的错串。
let oss_vector_millis : Int64 = 1792305684000L

///|
/// 独立实现算出的期望签名（四次 HMAC-SHA256 派生密钥 + 一次签名 HMAC）。
let oss_vector_signature : String = "c361c8590065f124e0bebcab26177983d0c331d842fc77ceeaf45b54abc73ecc"

///|
fn oss_vector_sign() -> @auth.Signature raise @error.OssError {
  let credentials = @auth.Credentials::new("test-ak", "test-sk")
  credentials.sign_at("cn-zhangjiakou", oss_vector_millis, @auth.RequestToSign::{
    verb: "GET",
    canonical_uri: "/moonfs/x.txt",
    query: [("acl", "")],
    headers: [
      ("host", "blog.oss-cn-zhangjiakou.aliyuncs.com"),
      ("x-oss-date", "20261018T064124Z"),
      ("x-oss-content-sha256", "UNSIGNED-PAYLOAD"),
    ],
  })
}

///|
test "ISO8601 基本格式与时区：固定毫秒进，定长串出" {
  let text = @auth.iso8601_basic(oss_vector_millis) catch {
    e => fail(e.text())
  }
  assert_eq(text, "20261018T064124Z")
}

///|
test "uri_encode：保留集、斜杠、空格与加号" {
  assert_eq(@auth.uri_encode("a/b c~d+e"), "a%2Fb%20c~d%2Be")
  assert_eq(@auth.uri_encode("a/b c", keep_slash=true), "a/b%20c")
  assert_eq(@auth.uri_encode("中文"), "%E4%B8%AD%E6%96%87")
}

///|
test "canonical_query_string：全部参数编码后按键排序，无值参数不带等号" {
  let text = @auth.canonical_query_string([
    ("prefix", "a b/c"),
    ("list-type", "2"),
    ("max-keys", "100"),
  ])
  assert_eq(text, "list-type=2&max-keys=100&prefix=a%20b%2Fc")
  assert_eq(@auth.canonical_query_string([("acl", "")]), "acl")
  assert_eq(
    @auth.canonical_query_string([("uploads", ""), ("acl", "")]),
    "acl&uploads",
  )
}

///|
test "canonical_headers：小写、排序、每行自带换行、host 被丢" {
  let block = @auth.canonical_headers([
    ("Content-Type", "text/plain"),
    ("X-OSS-Date", "20261018T064124Z"),
    ("host", "bucket.oss-cn-zhangjiakou.aliyuncs.com"),
  ])
  let expected = "content-type:text/plain\n" + "x-oss-date:20261018T064124Z\n"
  assert_eq(block.block, expected)
  assert_eq(block.signed_names, ["content-type", "x-oss-date"])
}

///|
test "必选头不进 AdditionalHeaders，其它头必须进" {
  let block = @auth.canonical_headers([
    ("host", "h.example"),
    ("x-oss-date", "20261018T064124Z"),
    ("x-oss-content-sha256", "UNSIGNED-PAYLOAD"),
    ("x-oss-meta-tool", "moon-oss"),
    ("x-moon-tag", "abc"),
  ])
  // `x-oss-*` 属于必选族：服务端自己就会把它算进去，声明了反而对不上。
  assert_eq(@auth.additional_headers(block.signed_names), "x-moon-tag")
  // 两个都在头块里——只是必选族不写进 AdditionalHeaders，不等于不入签。
  assert_true(block.block.contains("x-oss-meta-tool:moon-oss\n"))
  assert_true(block.block.contains("x-moon-tag:abc\n"))
}

///|
/// 六行形状按官方文式手推，两点都由真端点裁决过：
/// · `acl` 是**无值参数**，只写键名、不带 `=`（照 SigV4 的 `acl=` 抄会让每个子资源请求签不上）；
/// · 头块**不含 host**——上面传进去的那条 `("host", ...)` 必须被丢掉，
///   真桶读数：留着它，服务级 `GET /` 当场 403 `SignatureDoesNotMatch`（2026-10-18）。
/// `AdditionalHeaders` 这一格为空但**行还在**，少一行同样是签名不符。
test "canonical_request 六行逐字（host 不入签、空值参数不带等号）" {
  let expected = "GET\n" +
    "/moonfs/x.txt\n" +
    "acl\n" +
    "x-oss-content-sha256:UNSIGNED-PAYLOAD\n" +
    "x-oss-date:20261018T064124Z\n" +
    "\n" +
    "\n" +
    "UNSIGNED-PAYLOAD"
  let signature = oss_vector_sign() catch { e => fail(e.text()) }
  assert_eq(signature.canonical_request, expected)
  assert_true(!expected.contains("host:"))
}

///|
test "string_to_sign 四行：算法、时刻、scope、规范化串的哈希" {
  let signature = oss_vector_sign() catch { e => fail(e.text()) }
  let expected = "OSS4-HMAC-SHA256\n" +
    "20261018T064124Z\n" +
    "20261018/cn-zhangjiakou/oss/aliyun_v4_request\n" +
    @digest.sha256_hex(signature.canonical_request)
  assert_eq(signature.string_to_sign, expected)
  assert_eq(signature.scope, "20261018/cn-zhangjiakou/oss/aliyun_v4_request")
}

///|
/// 官方文档那条 PUT 示例给的是**规范化串的哈希**（不是签名值，因为示例里的 AK/SK 是掩码）。
/// 这条是本文件里唯一一份"作者之外的权威"给的期望值：它同时钉住三件事——
/// 六行形状、空查询参数那一格留空、以及 `content-disposition`／`content-length`
/// 这一族附加头既要进头块又要进 AdditionalHeaders。
test "官方文档示例：规范化串哈希逐字对上 c46d9639…" {
  let canonical = @auth.canonical_request(@auth.RequestToSign::{
    verb: "PUT",
    canonical_uri: "/examplebucket/exampleobject",
    query: [],
    headers: [
      ("Content-Disposition", "attachment"),
      ("Content-Length", "3"),
      ("Content-MD5", "ICy5YqxZB1uWSwcVLSNLcA=="),
      ("Content-Type", "text/plain"),
      ("x-oss-content-sha256", "UNSIGNED-PAYLOAD"),
      ("x-oss-date", "20250411T064124Z"),
      ("host", "examplebucket.oss-cn-hangzhou.aliyuncs.com"),
    ],
  })
  assert_eq(
    @digest.sha256_hex(canonical),
    "c46d96390bdbc2d739ac9363293ae9d710b14e48081fcb22cd8ad54b63136eca",
  )
  let block = @auth.canonical_headers([
    ("Content-Disposition", "attachment"),
    ("Content-Length", "3"),
    ("x-oss-date", "20250411T064124Z"),
  ])
  assert_eq(
    @auth.additional_headers(block.signed_names),
    "content-disposition;content-length",
  )
}

///|
/// 期望值来自那份独立实现，不是本实现自抄：签名对上，说明密钥链的**顺序、前缀、
/// scope 拼法**三处都与官方算法一致；Authorization 对上，说明字段分隔形状一致。
test "派生密钥链与签名值对上独立实现" {
  let signature = oss_vector_sign() catch { e => fail(e.text()) }
  assert_eq(signature.signature, oss_vector_signature)
  let head = "OSS4-HMAC-SHA256 Credential=" +
    "test-ak/20261018/cn-zhangjiakou/oss/aliyun_v4_request, " +
    "Signature=" +
    oss_vector_signature
  assert_eq(signature.authorization, head)
  assert_true(signature.additional_headers.is_empty())
}
