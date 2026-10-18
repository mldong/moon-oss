///|
/// OSS 的端点与区域。
///
/// 一条实测事实决定了这里的形状：**OSS 只收 virtual-hosted 寻址**——同一把凭据、同一个桶，
/// path 风格（`https://oss-<region>.aliyuncs.com/<bucket>/<key>`）一律回
/// 403 `SecondLevelDomainForbidden / Please use virtual hosted style to access.`
/// （2026-10-18 真桶现读）。所以本 SDK 不提供"寻址风格"开关：没有可选项的东西不做成配置，
/// 免得接入方以为关掉它就能绕过。

///|
pub(all) struct Config {
  /// "https" 或 "http"（真端点只该用 https）
  scheme : String
  /// 形如 `oss-cn-zhangjiakou.aliyuncs.com`，不带 scheme、不带桶名前缀
  endpoint_host : String
  /// 签名 scope 用的区域 id，如 `cn-zhangjiakou`
  region : String
  credentials : @auth.Credentials
}

///|
/// `endpoint` 接受带或不带 scheme 两种写法；带 `//` 或路径尾巴的直接拒——
/// 那类输入十有八九是把控制台的"访问域名"整串粘了过来。
pub fn Config::new(
  endpoint : String,
  region : String,
  credentials : @auth.Credentials,
) -> Config raise @error.OssError {
  if region.is_empty() {
    raise @error.BadParam("region is empty")
  }
  let trimmed = endpoint.trim().to_owned()
  if trimmed.is_empty() {
    raise @error.BadParam("endpoint is empty")
  }
  let scheme = if trimmed.has_prefix("https://") {
    "https"
  } else if trimmed.has_prefix("http://") {
    "http"
  } else {
    "https"
  }
  let rest = match trimmed.find("://") {
    None => trimmed
    Some(cut) => trimmed[cut + 3:trimmed.length()].to_owned()
  }
  let host = match rest.find("/") {
    None => rest
    Some(cut) => rest[0:cut].to_owned()
  }
  if host.is_empty() || host.contains(" ") || host.contains(":") {
    raise @error.BadParam("endpoint host is not usable: " + host)
  }
  Config::{ scheme, endpoint_host: host, region, credentials, }
}

///|
/// 桶级主机名（vhost）。空桶名就是服务级主机（`GET /` 列桶那一条）。
pub fn Config::host_of(self : Config, bucket : String) -> String {
  if bucket.is_empty() {
    self.endpoint_host
  } else {
    bucket + "." + self.endpoint_host
  }
}

///|
/// 请求 URL：`scheme://host/<编码后的键>`。键里的 `/` 保留（分段就是键的一部分）。
pub fn Config::url_of(
  self : Config,
  bucket : String,
  key~ : String = "",
) -> String {
  let base = self.scheme + "://" + self.host_of(bucket)
  if key.is_empty() {
    base + "/"
  } else {
    base + "/" + @auth.uri_encode(key, keep_slash=true)
  }
}

///|
/// 签名用的规范化路径。**这一条与 S3 的 SigV4 不同，而且容易踩**：OSS V4 的资源路径
/// 按"请求目标"算，与 URL 是 vhost 还是 path 风格无关——服务级 `/`、桶级 `/<bucket>/`、
/// 对象级 `/<bucket>/<key>`（官方 V4 页原文三行）。
/// 真桶读数：桶级列举按 `/` 签 ⇒ 403 `SignatureDoesNotMatch`，按 `/<bucket>/` 签 ⇒ 200
/// （服务级那一档两种写法都一样，所以只有带桶的请求会暴露这条差别）。
pub fn Config::canonical_uri_of(
  _self : Config,
  bucket : String,
  key~ : String = "",
) -> String {
  if bucket.is_empty() {
    "/"
  } else {
    let head = "/" + @auth.uri_encode(bucket)
    if key.is_empty() {
      head + "/"
    } else {
      head + "/" + @auth.uri_encode(key, keep_slash=true)
    }
  }
}

///|
pub fn Config::region_of(self : Config) -> String {
  self.region
}

///|
pub fn Config::credentials(self : Config) -> @auth.Credentials {
  self.credentials
}
