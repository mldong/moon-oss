///|
// 真端点档（凭据只从环境读，绝不打印值）。这一档才是六条待实测项的裁决处：
// 向量测试只能证明"我算得自洽"，真端点证明"OSS 认这个算法串"。
//
// Env: OSS_AK / OSS_SK / OSS_BUCKET / OSS_REGION。缺任何一项整段响亮跳过。

///|
fn live_env() -> (String, String, String, String)? {
  let names : Array[String] = ["OSS_AK", "OSS_SK", "OSS_BUCKET", "OSS_REGION"]
  let missing : Array[String] = []
  for name in names {
    if @env.get_env_var(name).unwrap_or("").is_empty() {
      missing.push(name)
    }
  }
  if missing.length() > 0 {
    println("missing: " + missing.join(", "))
    None
  } else {
    Some(
      (
        @env.get_env_var("OSS_AK").unwrap_or(""),
        @env.get_env_var("OSS_SK").unwrap_or(""),
        @env.get_env_var("OSS_BUCKET").unwrap_or(""),
        @env.get_env_var("OSS_REGION").unwrap_or(""),
      ),
    )
  }
}

///|
fn skip_note() -> Unit {
  println("SKIP live OSS check, OSS_* not supplied")
  println(
    "SKIP IS NOT A PASS: the native OSS signature was not measured by this run.",
  )
}

///|
fn endpoint_of(region : String) -> String {
  "https://oss-" + region + ".aliyuncs.com"
}

///|
fn build(
  ak : String,
  sk : String,
  region : String,
) -> @oss.Client raise @error.OssError {
  let credentials = @auth.Credentials::new(ak, sk)
  let config = @config.Config::new(endpoint_of(region), region, credentials)
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  @oss.Client::new(config, transport)
}

///|
/// 服务级列举的**读数串**：成功报条数，失败报错误文案。
/// 用 `return` 分叉是为了让两条臂都出 String——真端点那侧要的是读数，不是变体形状。
async fn probe_list_buckets(client : @oss.Client) -> String {
  let listing = client.list_buckets() catch {
    err => return "error:" + err.text()
  }
  "ok:" + listing.names.length().to_string() + " buckets"
}

///|
/// 桶级列举带三个非子资源查询参数（`list-type`／`max-keys`／`prefix`），
/// 这条通不过就是"全部查询参数入签"这条规则错了。
async fn probe_list_objects(client : @oss.Client, bucket : String) -> String {
  let listing = client.list_objects(bucket, prefix="moonfs-", max_keys=5) catch {
    err => return "error:" + err.text()
  }
  "ok:" +
  listing.keys.length().to_string() +
  " keys, truncated=" +
  listing.truncated.to_string()
}

///|
async test "真端点：V4 签名的服务级与桶级列举都要 200" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let buckets = probe_list_buckets(client)
      println("list_buckets " + buckets)
      assert_true(buckets.has_prefix("ok:"))
      let listing = probe_list_objects(client, environment.2)
      println("list_objects " + listing)
      assert_true(listing.has_prefix("ok:"))
    }
  }
}

///|
/// 负向判据：错密钥必须被**签名层**拒绝（`SignatureDoesNotMatch`）。
/// 若这里读到的是 `AccessDenied`，说明请求根本没走到验签，正向那条的"签名被认"就不成立。
async test "真端点：换错密钥必须报 SignatureDoesNotMatch，而不是含糊的 AccessDenied" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1 + "zz", environment.3) catch {
        err => fail("oss setup: " + err.text())
      }
      let reading = probe_list_buckets(client)
      println("wrong-secret reading=" + reading)
      if !reading.has_prefix("error:") {
        fail("wrong secret must not succeed: " + reading)
      }
      if !reading.contains("SignatureDoesNotMatch") {
        fail("expected the signature layer to reject it, got: " + reading)
      }
    }
  }
}
