///|
/// OSS 的错误形状。真 HTTP 读数只进 `Service` 那一臂，本地拒掉的走其它臂——
/// 把"没连上"和"服务端答了但拒绝"混成一个整数，重试策略就会被带偏（同 moon-kodo 的理由）。
pub(all) struct ServiceError {
  status : Int32
  /// 响应体 `<Error><Code>` 的读数；读不出时是空串
  code : String
  message : String
  /// `x-oss-request-id`，报障时要的那串
  request_id : String?
}

///|
pub(all) suberror OssError {
  BadParam(String)
  Network(String)
  /// 2xx 但回包缺必需字段：与"网络断"分开，与"服务端拒绝"也分开
  BadResponse(String)
  Service(ServiceError)
}

///|
/// 一行读数，供错误串与测试输出用。**不含**任何凭据。
pub fn OssError::text(self : OssError) -> String {
  match self {
    BadParam(m) => "oss bad-param: " + m
    Network(m) => "oss network: " + m
    BadResponse(m) => "oss bad-response: " + m
    Service(details) => {
      let head = details.status.to_string() + " " + details.code
      head + ": " + details.message
    }
  }
}

///|
/// 只读第一处 `<tag>…</tag>`。OSS 的错误与列表响应都是这一族简单形状，
/// 引一个完整 XML 解析器代价大于收益；但**读不到就是 `None`**，不静默给空值。
pub fn xml_first(text : String, tag : String) -> String? {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  match text.find(open) {
    None => None
    Some(start) => {
      let value_start = start + open.length()
      let tail = text[value_start:text.length()].to_owned()
      match tail.find(close) {
        None => None
        Some(offset) => {
          let end = value_start + offset
          Some(xml_unescape(text[value_start:end].to_owned()))
        }
      }
    }
  }
}

///|
/// 按文档序取每一处 `<tag>…</tag>`。
pub fn xml_all(text : String, tag : String) -> Array[String] {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  let out : Array[String] = []
  let mut cursor = 0
  while cursor < text.length() {
    let rest = text[cursor:text.length()].to_owned()
    match rest.find(open) {
      None => cursor = text.length()
      Some(open_at) => {
        let value_start = cursor + open_at + open.length()
        let tail = text[value_start:text.length()].to_owned()
        match tail.find(close) {
          None => cursor = text.length()
          Some(close_at) => {
            let value = text[value_start:value_start + close_at].to_owned()
            out.push(xml_unescape(value))
            cursor = value_start + close_at + close.length()
          }
        }
      }
    }
  }
  out
}

///|
/// 五个预定义实体（含十进制写法）。数值写法不能省：真端点在 ETag 里回 `&#34;…&#34;`
/// 是实测过的形状，只认命名写法会把服务端给的引号当成标签的一部分。
pub fn xml_unescape(text : String) -> String {
  let numeric = replace_all_pairs(text, [
    ("&#34;", "\""),
    ("&#39;", "'"),
    ("&#60;", "<"),
    ("&#62;", ">"),
  ])
  let lt = numeric.replace_all(old="&lt;", new="<")
  let gt = lt.replace_all(old="&gt;", new=">")
  let quot = gt.replace_all(old="&quot;", new="\"")
  let apos = quot.replace_all(old="&apos;", new="'")
  let amp = apos.replace_all(old="&amp;", new="&")
  amp.replace_all(old="&#38;", new="&")
}

///|
fn replace_all_pairs(text : String, pairs : Array[(String, String)]) -> String {
  let mut out = text
  for pair in pairs {
    out = out.replace_all(old=pair.0, new=pair.1)
  }
  out
}

///|
/// 错误体里的 `<Code>`，读不出给空串（调用方按空串走"非服务端错"那一档）。
pub fn xml_error_code(body : String) -> String {
  match xml_first(body, "Code") {
    Some(code) => code
    None => ""
  }
}
