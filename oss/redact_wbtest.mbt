///|
/// 错误文案这条纪律的用例：预签名 URL 的 query 是凭据本体，任何把它带进错误串的通道
/// 都要在出本库之前被隐去。传输层对 `InvalidRequest` 的几档文案是**原样嵌 url** 的
/// （`url 缺 :// 分隔`、`url 带 fragment`、`url 缺 authority`、`pathless query`），
/// 所以这一档不是假想敌。夹具里的键、签名、桶名全是我们编出来的串，不对应任何真凭据。

///|
test "问号之后一律隐去：x-oss-credential 与签名不出现在错误串里" {
  let leaky = "url 缺 :// 分隔：https://examplebucket-placeholder.oss-cn-hangzhou.aliyuncs.com/k.txt?x-oss-credential=LTAItestid00000000000000000000%2F20261023%2Fcn-hangzhou%2Foss%2Faliyun_v4_request&x-oss-date=20261023T000000Z&x-oss-expires=3600&x-oss-signature=deadbeefdeadbeefdeadbeefdeadbeefdead"
  let folded = redact_query(leaky)
  assert_true(folded.find("x-oss-credential") is None)
  assert_true(folded.find("x-oss-signature") is None)
  assert_true(folded.find("LTAItestid") is None)
  assert_true(
    folded.has_prefix(
      "url 缺 :// 分隔：https://examplebucket-placeholder.oss-cn-hangzhou.aliyuncs.com/k.txt?<redacted>",
    ),
  )
  // 隐去长在 redact_query 里没用——调用方读到的是 transport_text 的产物，这一档必须接上
  assert_true(
    transport_text(@transport.TransportError::InvalidRequest(leaky)).find(
      "x-oss-signature",
    )
    is None,
  )
}

///|
test "建连失败那一档本来只到源站，隐去这步不该动它一个字" {
  let detail = "建连失败（https://examplebucket-placeholder.oss-cn-hangzhou.aliyuncs.com）：TlsError"
  assert_eq(redact_query(detail), detail)
  assert_eq(
    transport_text(@transport.TransportError::Network(detail)),
    "network: " + detail,
  )
  assert_eq(transport_text(@transport.TransportError::Timeout), "timeout")
}
