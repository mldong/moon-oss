///|
// 新增能力的真桶档：缺 OSS_* 时整段 SKIP；有凭据时只写本轮自命名前缀，测量段红也先清扫再判红。

///|
fn extra_env() -> (String, String, String, String)? {
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
        @env.get_env_var("OSS_REGION").unwrap_or(""),
        @env.get_env_var("OSS_BUCKET").unwrap_or(""),
      ),
    )
  }
}

///|
fn extra_skip() -> Unit {
  println("SKIP live OSS extra checks, OSS_* not supplied")
  println("SKIP IS NOT A PASS: new OSS methods were not measured by this run.")
}

///|
fn extra_build(
  env : (String, String, String, String),
) -> @oss.Client raise @error.OssError {
  let credentials = @auth.Credentials::new(env.0, env.1)
  let config = @config.Config::new(
    "https://oss-" + env.2 + ".aliyuncs.com",
    env.2,
    credentials,
  )
  @oss.Client::new(config, @transport.AsyncHttpTransport::new())
}

///|
fn extra_tag() -> String {
  "moonfs-" + @auth.now_millis().to_string()
}

///|
fn extra_bytes(text : String) -> Bytes {
  @utf8.encode(text.view())
}

///|
fn extra_text(data : Bytes) -> String {
  @utf8.decode_lossy(data.exact_view())
}

///|
fn extra_status(err : @error.OssError) -> Int32 {
  match err {
    @error.OssError::Service(d) => d.status
    _ => -1
  }
}

///|
fn extra_has_tag(
  tags : Array[@oss.ObjectTag],
  key : String,
  value : String,
) -> Bool {
  let mut found = false
  for tag in tags {
    if tag.key == key && tag.value == value {
      found = true
    }
  }
  found
}

///|
async fn extra_cleanup(
  client : @oss.Client,
  bucket : String,
  keys : Array[String],
) -> Unit {
  for key in keys {
    let _ = client.delete_object(bucket, key) catch {
      err => println("cleanup " + key + ": " + err.text())
    }
  }
}

///|
async fn extra_abort(
  client : @oss.Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> Unit {
  if !upload_id.is_empty() {
    let _ = client.abort_multipart_upload(bucket, key, upload_id) catch {
      err => println("cleanup multipart " + key + ": " + err.text())
    }
  }
}

///|
async fn extra_get_status(
  client : @oss.Client,
  bucket : String,
  key : String,
  if_none_match~ : String,
) -> String {
  let _ = client.get_object(bucket, key, if_none_match~) catch {
    err => return "status:" + extra_status(err).to_string()
  }
  "ok"
}

///|
async fn extra_stat_status(
  client : @oss.Client,
  bucket : String,
  key : String,
) -> String {
  let _ = client.stat_object(bucket, key) catch {
    err => return "status:" + extra_status(err).to_string()
  }
  "ok"
}

///|
async test "真桶·标签/条件读/批量删除：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let exists = client.bucket_exists(bucket) catch {
        err => fail("bucket_exists: " + err.text())
      }
      if !exists {
        fail("bucket_exists returned false for the configured bucket")
      }
      let stamp = extra_tag()
      let k1 = stamp + "-tag-a.txt"
      let k2 = stamp + "-tag-b.txt"
      let keys : Array[String] = [k1, k2]
      let outcome = try {
        let _ = client.put_object(
          bucket,
          k1,
          extra_bytes("alpha"),
          content_type="text/plain",
        ) catch {
          err => fail("put a: " + err.text())
        }
        let _ = client.put_object(bucket, k2, extra_bytes("beta")) catch {
          err => fail("put b: " + err.text())
        }
        client.put_object_tagging(bucket, k1, [
          @oss.ObjectTag::{ key: "case", value: "tag", },
          @oss.ObjectTag::{ key: "env", value: "live", },
        ]) catch {
          err => fail("put tagging: " + err.text())
        }
        let tagging = client.get_object_tagging(bucket, k1) catch {
          err => fail("get tagging: " + err.text())
        }
        if tagging.tags.length() != 2 {
          fail("tag count: " + tagging.tags.length().to_string())
        }
        if !extra_has_tag(tagging.tags, "case", "tag") {
          fail("tag case missing: " + tagging.body)
        }
        let stat = client.stat_object(bucket, k1) catch {
          err => fail("stat: " + err.text())
        }
        let etag = match stat.etag {
          Some(value) => value
          None => fail("stat has no etag")
        }
        let got = client.get_object(bucket, k1, if_match=etag) catch {
          err => fail("conditional get: " + err.text())
        }
        if extra_text(got.body) != "alpha" {
          fail("conditional get body mismatch")
        }
        let blocked = extra_get_status(client, bucket, k1, if_none_match=etag)
        if blocked != "status:304" {
          fail("if-none-match expected 304, got " + blocked)
        }
        let deleted = client.delete_objects(bucket, keys) catch {
          err => fail("delete_objects: " + err.text())
        }
        if deleted.deleted.length() != 2 || deleted.errors.length() != 0 {
          fail(
            "delete_objects deleted=" +
            deleted.deleted.length().to_string() +
            " errors=" +
            deleted.errors.length().to_string(),
          )
        }
        let after = extra_stat_status(client, bucket, k1)
        if after != "status:404" {
          fail("deleted key still stat-able: " + after)
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, keys)
      println("oss extra tagging/batch outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·分片复制与未完成分片列举：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let stamp = extra_tag()
      let src = stamp + "-copy-src.bin"
      let dst = stamp + "-copy-dst.bin"
      let keys : Array[String] = [src, dst]
      let mut upload_id = ""
      let payload = Bytes::from_array(Array::make(1048576, b'a'))
      let outcome = try {
        let _ = client.put_object(bucket, src, payload) catch {
          err => fail("put source: " + err.text())
        }
        upload_id = client.create_multipart_upload(bucket, dst) catch {
          err => fail("create multipart: " + err.text())
        }
        let listed = client.list_multipart_uploads(bucket, prefix=dst) catch {
          err => fail("list multipart: " + err.text())
        }
        let mut seen = false
        for upload in listed.uploads {
          if upload.key == dst && upload.upload_id == upload_id {
            seen = true
          }
        }
        if !seen {
          fail("multipart upload not listed: " + listed.body)
        }
        let part = client.upload_part_copy(
          bucket,
          src,
          bucket,
          dst,
          upload_id,
          1,
          copy_source_range="bytes=0-1048575",
        ) catch {
          err => fail("upload_part_copy: " + err.text())
        }
        let _ = client.complete_multipart_upload(bucket, dst, upload_id, [
          (1, part.etag),
        ]) catch {
          err => fail("complete: " + err.text())
        }
        upload_id = ""
        let stat = client.stat_object(bucket, dst) catch {
          err => fail("stat target: " + err.text())
        }
        if stat.size != 1048576L {
          fail("target size " + stat.size.to_string())
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_abort(client, bucket, dst, upload_id)
      extra_cleanup(client, bucket, keys)
      println("oss extra multipart outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·存储类/自动 MD5/版本与 CORS 读：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-opts.txt"
      let outcome = try {
        let _ = client.put_object(
          bucket,
          key,
          extra_bytes("opts payload"),
          content_type="text/plain",
          storage_class="Standard",
          compute_md5=true,
        ) catch {
          err => fail("put with storage class/md5: " + err.text())
        }
        let got = client.get_object(bucket, key) catch {
          err => fail("get after opts put: " + err.text())
        }
        if extra_text(got.body) != "opts payload" {
          fail("opts body mismatch")
        }
        let stat = client.stat_object(bucket, key) catch {
          err => fail("stat after opts put: " + err.text())
        }
        match stat.storage_class {
          Some(value) => assert_eq(value, "Standard")
          None => fail("stat has no storage class")
        }
        let listing = client.list_objects(bucket, prefix=key, max_keys=10) catch {
          err => fail("list after opts put: " + err.text())
        }
        let mut listed_class = ""
        for object in listing.objects {
          if object.key == key {
            listed_class = object.storage_class.unwrap_or("")
          }
        }
        assert_eq(listed_class, "Standard")
        let _ = client.get_bucket_versioning(bucket) catch {
          err => fail("get bucket versioning: " + err.text())
        }
        let _ = client.get_bucket_cors(bucket) catch {
          err => fail("get bucket cors: " + err.text())
        }
        let lifecycle = client.get_bucket_lifecycle(bucket) catch {
          err => fail("get bucket lifecycle: " + err.text())
        }
        println("oss lifecycle rules=" + lifecycle.length().to_string())
        let referer = client.get_bucket_referer(bucket) catch {
          err => fail("get bucket referer: " + err.text())
        }
        let policy = client.get_bucket_policy(bucket) catch {
          err => fail("get bucket policy: " + err.text())
        }
        let replication = client.get_bucket_replication(bucket) catch {
          err => fail("get bucket replication: " + err.text())
        }
        let inventories = client.list_bucket_inventories(bucket) catch {
          err => fail("list bucket inventories: " + err.text())
        }
        let acceleration = client.get_bucket_transfer_acceleration(bucket) catch {
          err => fail("get transfer acceleration: " + err.text())
        }
        let cnames = client.list_bucket_cnames(bucket) catch {
          err => fail("list bucket cnames: " + err.text())
        }
        let location = client.get_bucket_location(bucket) catch {
          err => fail("get bucket location: " + err.text())
        }
        let info = client.get_bucket_info(bucket) catch {
          err => fail("get bucket info: " + err.text())
        }
        let payer = client.get_bucket_request_payment(bucket) catch {
          err => fail("get request payment: " + err.text())
        }
        let group = client.get_bucket_resource_group(bucket) catch {
          err => fail("get bucket resource group: " + err.text())
        }
        println("oss resource group=" + group.unwrap_or("<none>"))
        println(
          "oss location=" +
          location.unwrap_or("<none>") +
          " bucket_region=" +
          info.region.unwrap_or("<none>") +
          " payer=" +
          payer.unwrap_or("<none>"),
        )
        println("oss cnames=" + cnames.length().to_string())
        println(
          "oss transfer acceleration configured=" +
          (acceleration is Some(_)).to_string(),
        )
        let missing_inventory = client.get_bucket_inventory(
          bucket, "moonfs-probe-missing",
        ) catch {
          err => fail("get missing inventory: " + err.text())
        }
        println(
          "oss inventories=" +
          inventories.length().to_string() +
          " missing=" +
          (missing_inventory is None).to_string(),
        )
        println(
          "oss bucket replication configured=" +
          (replication is Some(_)).to_string(),
        )
        println(
          "oss bucket policy configured=" + (policy is Some(_)).to_string(),
        )
        println(
          "oss referer whitelist=" + referer.referers.length().to_string(),
        )
        let server_crc = client.object_crc64(bucket, key) catch {
          err => fail("object crc64: " + err.text())
        }
        let local_crc = @oss.crc64_decimal(
          @oss.crc64_xz(extra_bytes("opts payload")),
        )
        match server_crc {
          Some(value) =>
            if value != local_crc {
              fail("crc64 mismatch: server=" + value + " local=" + local_crc)
            }
          None => fail("HEAD returned no crc64 header")
        }
        let _ = client.get_bucket_acl(bucket) catch {
          err => fail("get bucket acl: " + err.text())
        }
        let _ = client.get_bucket_tagging(bucket) catch {
          err => fail("get bucket tagging: " + err.text())
        }
        let _ = client.get_bucket_logging(bucket) catch {
          err => fail("get bucket logging: " + err.text())
        }
        let _ = client.get_bucket_website(bucket) catch {
          err => fail("get bucket website: " + err.text())
        }
        let _ = client.get_bucket_encryption(bucket) catch {
          err => fail("get bucket encryption: " + err.text())
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key])
      println("oss extra opts outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·追加写：两次 append 读回拼接内容" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-append.txt"
      let outcome = try {
        let first = client.append_object(
          bucket,
          key,
          extra_bytes("hello"),
          position=0L,
          content_type="text/plain",
        ) catch {
          err => fail("append first: " + err.text())
        }
        println(
          "oss append next1=" + first.next_position.unwrap_or(-1L).to_string(),
        )
        let second = client.append_object(
          bucket,
          key,
          extra_bytes(" world"),
          position=first.next_position.unwrap_or(5L),
          content_type="text/plain",
        ) catch {
          err => fail("append second: " + err.text())
        }
        println(
          "oss append next2=" + second.next_position.unwrap_or(-1L).to_string(),
        )
        let got = client.get_object(bucket, key) catch {
          err => fail("get appended: " + err.text())
        }
        if extra_text(got.body) != "hello world" {
          fail("append body mismatch: " + extra_text(got.body))
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key])
      println("oss extra append outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·PostObject V4/V1 表单：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let tag = extra_tag()
      let key = tag + "-post-v4.txt"
      let v1_key = tag + "-post-v1.txt"
      let outcome = try {
        // 默认档就是 V4（x-oss-signature-version 那一族）
        let post = client.post_object(
          bucket,
          key,
          extra_bytes("post payload"),
          content_type="text/plain",
          success_action_status=201,
        ) catch {
          err => fail("post_object v4: " + err.text())
        }
        if post.status != 201 {
          fail("post v4 status " + post.status.to_string())
        }
        if post.etag is None {
          fail("post v4 has no etag")
        }
        let got = client.get_object(bucket, key) catch {
          err => fail("get after v4 post: " + err.text())
        }
        if extra_text(got.body) != "post payload" {
          fail("post v4 body mismatch")
        }
        let legacy = client.post_object(
          bucket,
          v1_key,
          extra_bytes("post v1 payload"),
          content_type="text/plain",
          success_action_status=201,
          signature_version="v1",
        ) catch {
          err => fail("post_object v1: " + err.text())
        }
        if legacy.status != 201 {
          fail("post v1 status " + legacy.status.to_string())
        }
        let v1_got = client.get_object(bucket, v1_key) catch {
          err => fail("get after v1 post: " + err.text())
        }
        if extra_text(v1_got.body) != "post v1 payload" {
          fail("post v1 body mismatch")
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key, v1_key])
      println("oss extra post outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·软链接：建链读目标，删链不删目标" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let tag = extra_tag()
      let target = tag + "-symlink-target.txt"
      let link = tag + "-symlink.txt"
      let outcome = try {
        let _ = client.put_object(
          bucket,
          target,
          extra_bytes("symlink target payload"),
        ) catch {
          err => fail("put target: " + err.text())
        }
        client.put_symlink(bucket, link, target) catch {
          err => fail("put_symlink: " + err.text())
        }
        let info = client.get_symlink(bucket, link) catch {
          err => fail("get_symlink: " + err.text())
        }
        match info.target {
          Some(value) => assert_eq(value, target)
          None => fail("symlink has no target header")
        }
        let got = client.get_object(bucket, link) catch {
          err => fail("get through symlink: " + err.text())
        }
        if extra_text(got.body) != "symlink target payload" {
          fail("symlink body mismatch")
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [link, target])
      println("oss extra symlink outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
fn auto_filler(total : Int32) -> Bytes {
  let block = "moon-auto-filler-0123456789abcdef-"
  let mut out = block
  while out.length() < total {
    out = out + out
  }
  @utf8.encode(out[0:total].to_owned())
}

///|
async test "真桶·一条式上传：超过阈值自动分片并合完" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-auto.bin"
      let seen : Array[Int32] = []
      let payload = auto_filler(256000)
      let outcome = try {
        let put = client.put_bytes_auto(
          bucket,
          key,
          payload,
          part_size=102400,
          threshold=102400,
          content_type="application/octet-stream",
          progress=Some(fn(sent, _total) { seen.push(sent) }),
        ) catch {
          err => fail("put_bytes_auto: " + err.text())
        }
        if put.etag.is_empty() {
          fail("auto upload returned an empty etag")
        }
        let got = client.get_object(bucket, key) catch {
          err => fail("get after auto upload: " + err.text())
        }
        if got.body.length() != payload.length() {
          fail(
            "auto upload size mismatch: " +
            got.body.length().to_string() +
            " != " +
            payload.length().to_string(),
          )
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      if outcome == "no-error" && seen.length() < 2 {
        fail(
          "progress callback fired fewer than twice: " +
          seen.length().to_string(),
        )
      }
      extra_cleanup(client, bucket, [key])
      println("moon-oss auto upload outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·翻页器：按前缀把所有对象翻完" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let root = extra_tag() + "-pager/"
      let keys = [root + "a.txt", root + "b.txt", root + "c.txt"]
      for key in keys {
        let _ = client.put_object(bucket, key, extra_bytes("pager")) catch {
          err => fail("put: " + err.text())
        }
      }
      let listing = client.list_all_objects(bucket, prefix=root, max_keys=1) catch {
        err => fail("list all: " + err.text())
      }
      let mut seen = 0
      for item in listing.objects {
        if item.key.has_prefix(root) {
          seen = seen + 1
        }
      }
      println("pager seen=" + seen.to_string())
      if seen != keys.length() {
        fail("pager missed objects: " + seen.to_string())
      }
      extra_cleanup(client, bucket, keys)
    }
  }
}

///|
async test "真桶·对象内查询 CSV：原始事件流非空" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-select.csv"
      let _ = client.put_object(
        bucket,
        key,
        extra_bytes("name,age\nalice,30\nbob,25\n"),
        content_type="text/csv",
      ) catch {
        err => fail("put csv: " + err.text())
      }
      let stream = client.select_object_csv(
        bucket, key, "SELECT * FROM OSSOBJECT",
      ) catch {
        err => fail("select: " + err.text())
      }
      println("select bytes=" + stream.length().to_string())
      extra_cleanup(client, bucket, [key])
      if stream.length() == 0 {
        fail("select returned an empty event stream")
      }
    }
  }
}

///|
async test "真桶·断点续传：先传第一片，再带状态续完" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-resume.bin"
      let payload = auto_filler(256000)
      let part_size = 102400
      let upload_id = client.create_multipart_upload(bucket, key) catch {
        err => fail("create: " + err.text())
      }
      let first = client.upload_part(
        bucket,
        key,
        upload_id,
        1,
        payload[0:part_size].to_owned(),
      ) catch {
        err => fail("part1: " + err.text())
      }
      let resumed = client.put_bytes_resumable(
        bucket,
        key,
        payload,
        part_size~,
        threshold=part_size,
        resume_upload_id=upload_id,
        resume_offset=part_size,
        resume_parts=[(1, first)],
      ) catch {
        err => fail("resume upload: " + err.text())
      }
      if resumed.error is Some(_) {
        fail("resume upload error: " + resumed.error.unwrap())
      }
      let got = client.get_object(bucket, key) catch {
        err => fail("get after resume: " + err.text())
      }
      let ok = got.body.length() == payload.length()
      extra_cleanup(client, bucket, [key])
      if !ok {
        fail(
          "resume size mismatch: " +
          got.body.length().to_string() +
          " != " +
          payload.length().to_string(),
        )
      }
    }
  }
}
