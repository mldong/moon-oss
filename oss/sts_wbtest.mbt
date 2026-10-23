///|
test "presigned URLs carry the sts token in the query" {
  let credentials = @auth.Credentials::new("ak", "sk").with_security_token(
    "token-1",
  )
  let config = @config.Config::new(
    "https://oss-cn-hangzhou.aliyuncs.com", "cn-hangzhou", credentials,
  )
  let client = Client::new(config, @transport.AsyncHttpTransport::new())
  let url = client.presigned_get_url("b", "k") catch {
    _ => abort("presign must work with an sts token")
  }
  assert_true(url.contains("security-token=token-1"))
}
