///|
/// 阿里云 OSS 的 **V4 签名**（`OSS4-HMAC-SHA256`）。规范取自官方
/// "在 Header 中包含 V4 签名（推荐）"一页，逐条对应关系写在下面每个函数上。
///
/// 为什么时间戳是入参而不是内部取时钟：签名向量测试必须能钉死一整个"请求→签名"样本，
/// 挂在 `now()` 上的测试既不可复现，也分不清"签名算错"与"时钟漂移"。

///|
/// 参与一次签名所需的全部输入。字段刻意做成"调用方已经决定好的形状"：
/// 寻址风格（vhost 还是 path）由 `config` 那层决定并拼进 `canonical_uri`/`host`，
/// 签名器不管——两代的差别只在拼串，混进来就会两处各错一半。
pub(all) struct RequestToSign {
  /// 大写的 HTTP 动词，如 "GET"／"PUT"
  verb : String
  /// 规范化后的资源路径：vhost 风格下是 "/<编码后的键>"，服务级是 "/"
  canonical_uri : String
  /// 查询参数（未编码的原值）。V4 与 V1 的关键差别就在这条上，见 `canonical_query_string`
  query : Array[(String, String)]
  /// 参与签名的头，原样大小写都行（内部统一转小写并排序）。
  /// `host`／`authorization` 传进来也会被丢掉——见 `is_unsigned_header` 那条实测
  headers : Array[(String, String)]
}

///|
/// 一次签名的全部读数。`canonical_request` 与 `string_to_sign` 都留着：
/// 排障时这两串就是证据，而它们**不含任何密钥**。
pub(all) struct Signature {
  authorization : String
  /// 参与签名但非必选的头名列表（字典序、分号分隔）；没有就是空串，此时不发出该字段
  additional_headers : String
  scope : String
  timestamp : String
  canonical_request : String
  string_to_sign : String
  signature : String
}

///|
/// 头块 + 参与签名的头名（字典序）。返回类型必须是命名结构：
/// 匿名结构体不能出现在顶层签名的返回位置。
pub(all) struct HeaderBlock {
  block : String
  signed_names : Array[String]
}

///|
/// 必选头族（官方 V4 页现读）：`content-md5`、`content-type`、以及全部 `x-oss-*`。
/// 这一族的用途是"要不要写进 AdditionalHeaders"——服务端自己就会把它们算进签名，
/// 声明了反而对不上。
///
/// **`host` 不在这一族，而且它根本不入签**：AWS SigV4 把 host 列为必签头，OSS V4 没有，
/// 官方那条 PUT 示例的规范化头块里就没有 `host:` 一行。这条不是照抄文档推的——
/// 真桶读数：把 host 算进头块，服务级 `GET /` 当场 403 `SignatureDoesNotMatch`；
/// 撤掉之后同一条请求 200（2026-10-18）。
fn is_mandatory_header(name : String) -> Bool {
  match name {
    "content-type" => true
    "content-md5" => true
    _ => name.has_prefix("x-oss-")
  }
}

///|
/// 一律不入签的头：`authorization` 是签名结果的载体，签它自己就成了循环；
/// `host` 见上面那条实测。
fn is_unsigned_header(name : String) -> Bool {
  name == "host" || name == "authorization"
}

///|
/// 规范化资源路径的编码：`A-Za-z0-9-_.~` 之外全部 `%XX`（大写十六进制），空格是 `%20`
/// 而不是 `+`。`keep_slash` 为真时 `/` 原样保留——对象键的分段就是这个意思。
pub fn uri_encode(text : String, keep_slash~ : Bool = false) -> String {
  if !keep_slash {
    return @percent.encode(text.view())
  }
  let mut out = ""
  let mut first = true
  for segment in text.split("/") {
    if !first {
      out = out + "/"
    }
    first = false
    out = out + @percent.encode(segment)
  }
  out
}

///|
/// ASCII 码位比较折成 -1/0/1。不能直接用 core 的 `String.compare`：它先比长度再比内容，
/// 拿来排序查询串会把 `b` 排到 `aa` 后面，签名当场对不上。
fn compare_string(a : String, b : String) -> Int32 {
  let ac = a.to_array()
  let bc = b.to_array()
  let n = if ac.length() < bc.length() { ac.length() } else { bc.length() }
  let mut i = 0
  while i < n {
    let x = ac[i].to_int()
    let y = bc[i].to_int()
    if x < y {
      return -1
    }
    if x > y {
      return 1
    }
    i = i + 1
  }
  ac.length() - bc.length()
}

///|
/// 同键先按值排；排序对象是**编码后**的形状。
fn compare_pair(a : (String, String), b : (String, String)) -> Int32 {
  let by_key = compare_string(a.0, b.0)
  if by_key == 0 {
    compare_string(a.1, b.1)
  } else {
    by_key
  }
}

///|
/// 插入排序：这里的数组都是个位数长度，用库排序还要引入 `Ordering` 类型名，
/// 反而多一处会错的地方。
fn[T] insertion_sort(items : Array[T], less : (T, T) -> Bool) -> Array[T] {
  let sorted : Array[T] = []
  for item in items {
    let mut placed = false
    let mut index = 0
    while index < sorted.length() && !placed {
      if less(item, sorted[index]) {
        placed = true
      } else {
        index = index + 1
      }
    }
    sorted.insert(index, item)
  }
  sorted
}

///|
fn is_space(c : Char) -> Bool {
  let x = c.to_int()
  x == 32 || x == 9 || x == 10 || x == 13
}

///|
/// 头值归一：去首尾空白、内部连续空白折成一个空格。签名算的是这一串，
/// 发出去的是另一串，两边规则不同就会各对一半。
pub fn normalize_header_value(value : String) -> String {
  let chars = value.to_array()
  let mut start = 0
  while start < chars.length() && is_space(chars[start]) {
    start = start + 1
  }
  let mut end = chars.length()
  while end > start && is_space(chars[end - 1]) {
    end = end - 1
  }
  let out : Array[Char] = []
  let mut pending_space = false
  for i in start..<end {
    let c = chars[i]
    if is_space(c) {
      pending_space = true
    } else {
      if pending_space && !out.is_empty() {
        out.push(' ')
      }
      pending_space = false
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// 规范化查询串：键与值各自编码，按**编码后的键**字典序排（同键再按值排），`&` 连接。
/// 无值参数（`?acl`／`?uploads`）只写编码后的**键名，不带 `=`**——官方 V4 页的原文是
/// "单个 key 时就是 UriEncode(key)"。这一条与 AWS SigV4 的 `key=` 形状不同，
/// 照 SigV4 抄会让每一个子资源请求都签不上。
///
/// 待实测项第 1 条的裁决：**全部**查询参数入签（V1 只算子资源）。live 档用真端点验
/// `prefix`／`max-keys`／`list-type`；子资源那条由 `?acl` 这一档验（见 oss 包的 live 用例）。
pub fn canonical_query_string(query : Array[(String, String)]) -> String {
  if query.is_empty() {
    return ""
  }
  let encoded : Array[(String, String)] = []
  for pair in query {
    encoded.push((uri_encode(pair.0), uri_encode(pair.1)))
  }
  let ordered = insertion_sort(encoded, (a, b) => compare_pair(a, b) < 0)
  let mut out = ""
  for i in 0..<ordered.length() {
    if i > 0 {
      out = out + "&"
    }
    let key = ordered[i].0
    let value = ordered[i].1
    let piece = if value.is_empty() { key } else { key + "=" + value }
    out = out + piece
  }
  out
}

///|
/// 规范化头块：**除 `is_unsigned_header` 那一族之外，传进来的头全部入签**
/// （名字统一小写、值归一，按名字字典序，**每行自带换行**）。
/// 必选族（`content-type`／`content-md5`／`x-oss-*`）由服务端自己认定；
/// 不在那一族里的头必须同时出现在 `AdditionalHeaders` 里，否则服务端重算时不会把它
/// 算进去，签名当场对不上。所以这里不做"只收必选族"的过滤——过滤了就等于悄悄丢了一格。
pub fn canonical_headers(headers : Array[(String, String)]) -> HeaderBlock {
  let rows : Array[(String, String)] = []
  for pair in headers {
    let name = trim_ascii(pair.0).to_lower()
    let value = trim_ascii(pair.1)
    if !name.is_empty() && !is_unsigned_header(name) {
      rows.push((name, value))
    }
  }
  let ordered = insertion_sort(rows, (a, b) => compare_string(a.0, b.0) < 0)
  let mut block = ""
  let names : Array[String] = []
  for pair in ordered {
    block = block + pair.0 + ":" + normalize_header_value(pair.1) + "\n"
    names.push(pair.0)
  }
  HeaderBlock::{ block, signed_names: names, }
}

///|
/// 头名/头值两侧的首尾空白。`String.trim` 给的是 `StringView`，
/// 这里要的是能继续拼装的 `String`。
fn trim_ascii(text : String) -> String {
  text.trim().to_owned()
}

///|
/// 必选头之外**额外**参与签名的头名，写进 `AdditionalHeaders`。
/// 规则现读：小写、字典序、分号分隔；一个都没有时是空串（该字段不发出，但规范化
/// 请求里那一行仍占位——少一行就是签名不符）。
pub fn additional_headers(signed : Array[String]) -> String {
  let extras : Array[String] = []
  for name in signed {
    if !is_mandatory_header(name) {
      extras.push(name)
    }
  }
  let ordered = insertion_sort(extras, (a, b) => compare_string(a, b) < 0)
  let mut out = ""
  for i in 0..<ordered.length() {
    if i > 0 {
      out = out + ";"
    }
    out = out + ordered[i]
  }
  out
}

///|
/// 完整六行。行与行之间各有一个换行，头块自身已以换行结尾——
/// 少一个或多一个都是签名不符，所以这里逐行绑定，不在拼装表达式里随手加分隔。
pub fn canonical_request(req : RequestToSign) -> String {
  let headers = canonical_headers(req.headers)
  let line1 = req.verb + "\n"
  let line2 = req.canonical_uri + "\n"
  let line3 = canonical_query_string(req.query) + "\n"
  let line4 = headers.block + "\n"
  let line5 = additional_headers(headers.signed_names) + "\n"
  let line6 = unsigned_payload
  line1 + line2 + line3 + line4 + line5 + line6
}

///|
/// 正文哈希这一格现读只支持 `UNSIGNED-PAYLOAD`（官方 V4 页），所以签名不读正文。
pub let unsigned_payload : String = "UNSIGNED-PAYLOAD"

///|
pub fn scope_of(date : String, region : String) -> String {
  date + "/" + region + "/oss/aliyun_v4_request"
}

///|
/// 派生密钥链（官方原样）：
/// `HMAC(HMAC(HMAC(HMAC("aliyun_v4"+SK, Date), Region), "oss"), "aliyun_v4_request")`
pub fn signing_key(
  secret_key : String,
  date : String,
  region : String,
) -> Bytes {
  let key0 = @digest.hmac_sha256_of_bytes(
    @utf8.encode(("aliyun_v4" + secret_key).view()),
    @utf8.encode(date.view()),
  )
  let key1 = @digest.hmac_sha256_of_bytes(key0, @utf8.encode(region.view()))
  let key2 = @digest.hmac_sha256_of_bytes(key1, @utf8.encode("oss".view()))
  @digest.hmac_sha256_of_bytes(key2, @utf8.encode("aliyun_v4_request".view()))
}

///|
/// `timestamp` 必须是 ISO8601 基本格式（`YYYYMMDDTHHMMSSZ`，UTC），日期段直接前缀取。
pub fn sign_v4(
  access_key : String,
  secret_key : String,
  region : String,
  timestamp : String,
  req : RequestToSign,
) -> Signature raise @error.OssError {
  if timestamp.length() < 15 {
    raise @error.BadParam(
      "timestamp must be YYYYMMDDTHHMMSSZ, got " + timestamp,
    )
  }
  if access_key.is_empty() || secret_key.is_empty() {
    raise @error.BadParam("both keys are required to sign")
  }
  let date = timestamp[0:8].to_owned()
  let scope = scope_of(date, region)
  let canonical = canonical_request(req)
  let headers = canonical_headers(req.headers)
  let extras = additional_headers(headers.signed_names)
  let algorithm = "OSS4-HMAC-SHA256"
  let credential = access_key + "/" + scope
  let string_to_sign = algorithm +
    "\n" +
    timestamp +
    "\n" +
    scope +
    "\n" +
    @digest.sha256_hex(canonical)
  let signature = @digest.hmac_sha256_hex_of_bytes(
    signing_key(secret_key, date, region),
    @utf8.encode(string_to_sign.view()),
  )
  let head = algorithm + " Credential=" + credential
  let authorization = if extras.is_empty() {
    head + ", Signature=" + signature
  } else {
    head + ", AdditionalHeaders=" + extras + ", Signature=" + signature
  }
  Signature::{
    authorization,
    additional_headers: extras,
    scope,
    timestamp,
    canonical_request: canonical,
    string_to_sign,
    signature,
  }
}

///|
/// ISO8601 基本格式（`20261018T064124Z`），OSS V4 的 `x-oss-date` 与 StringToSign 都用它。
/// 时钟是入参：向量测试要能钉住一个时刻，不能挂在 `now()` 上。
/// 区名写死 "UTC"——签名协议要的是 UTC 读数，读本机时区会签出一个"看着对"的错串。
pub fn iso8601_basic(millis : Int64) -> String raise @error.OssError {
  match @date.now_at("UTC", @date.clock_fixed(millis)) {
    None =>
      raise @error.BadParam(
        "epoch millis outside the zone table: " + millis.to_string(),
      )
    Some(dt) => {
      let day = dt.date
      let year = pad(day.year, 4)
      let month = pad(day.month, 2)
      let date_of_day = pad(day.day, 2)
      let hour = pad(dt.hour, 2)
      let minute = pad(dt.minute, 2)
      let second = pad(dt.second, 2)
      year + month + date_of_day + "T" + hour + minute + second + "Z"
    }
  }
}

///|
fn pad(value : Int32, width : Int32) -> String {
  let text = value.to_string()
  let mut missing = width - text.length()
  if missing <= 0 {
    return text
  }
  let mut zeros = ""
  while missing > 0 {
    zeros = zeros + "0"
    missing = missing - 1
  }
  zeros + text
}
