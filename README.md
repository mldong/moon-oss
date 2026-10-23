# mldong/moon-oss

阿里云对象存储（OSS）**原生协议**客户端的 MoonBit 版，签名走官方推荐的 V4
（`OSS4-HMAC-SHA256`）。它不认识存储核心层的 `FileInfo`，也不依赖任何上层——纯对象操作、
备份、静态站发布都可以直接用。

这不是"把 S3 兼容层换个端点"：OSS 的 S3 兼容层写入侧会被授权层拒，而原生协议这一族
（`x-oss-*` 头、V4 查询串签名、`x-oss-copy-source`）本来就与 SigV4 不同名、不同形状。

## 最小用法

```moonbit
test "V4 的两条出口都由注入的时刻决定：Authorization 串与预签名查询串" {
  let credentials = @ossauth.Credentials::new("ak-example", "sk-example")
  let request = @ossauth.RequestToSign::{
    verb: "GET",
    canonical_uri: "/demo-bucket/note.txt",
    query: [("acl", "")],
    headers: [("x-oss-date", "20261018T064124Z")],
  }
  let signed = credentials.sign_at("cn-zhangjiakou", 1792305684000L, request)
  assert_eq(signed.scope, "20261018/cn-zhangjiakou/oss/aliyun_v4_request")
  assert_true(signed.authorization.has_prefix(
    "OSS4-HMAC-SHA256 Credential=ak-example/20261018/cn-zhangjiakou/oss/aliyun_v4_request",
  ))
  let presigned = credentials.presign_at(
    "cn-zhangjiakou",
    "20261018T064124Z",
    600L,
    request,
  )
  assert_true(presigned.query.contains("x-oss-signature="))
  let config = @ossconfig.Config::new(
    "https://oss-cn-zhangjiakou.aliyuncs.com",
    "cn-zhangjiakou",
    credentials,
  )
  assert_eq(config.host_of("demo-bucket"), "demo-bucket.oss-cn-zhangjiakou.aliyuncs.com")
  assert_eq(config.canonical_uri_of("demo-bucket", key="note.txt"), "/demo-bucket/note.txt")
  let _client = @sdk.Client::new(config, @transport.AsyncHttpTransport::new())
}
```

时钟是入参而不是内部取 `now()`：这样"请求→签名"整条链能被钉成一份可复现的样本，
出问题时分得清是签名算错还是时钟漂移。真请求走 `Client` 上那些方法，它们自己读时钟。

凭据类型刻意不派生 `Debug` 与 `ToJson`：一个"打印出来看看"的调试语句就把密钥写进日志了。

## 寻址风格没有开关

OSS 只收虚主机风格（`https://<桶>.oss-<区域>.aliyuncs.com/<键>`），path 风格一律回
403 `SecondLevelDomainForbidden`（真桶现读）。没有可选项的东西不做成配置——
接入方以为关掉它就能绕过，反而多一类错。

签名里那条"规范化资源路径"因此与 URL 形状无关，它按**请求目标**算：服务级 `/`、
桶级 `/<桶>/`、对象级 `/<桶>/<键>`。这一条与 AWS SigV4 相反，照 SigV4 抄会全线 403。

## 覆盖的族

对象读写与删除、条件读（Range）、列举（ListObjects V2，含前缀／分隔符／续页符）、
手动分片五步、分片复制与未完成分片列举、预签名 GET 与 PUT、对象 ACL 读写、服务级列桶、
批量删除、对象标签、条件请求、自动 Content-MD5 与 CRC64 读回、存储类、追加写、软链接、
表单上传（V4 默认，V1 兼容）、归档解冻，以及桶 CRUD 与桶配置（ACL／版本／CORS／标签／
日志／网站／加密／生命周期／防盗链）。

`?acl`／`?uploads` 这类**无值参数**在规范化查询串里只写键名、不带 `=`——又是与 SigV4
相反的一处，两处形状都各有真桶读数钉着。

## 开发进度

排法按消费方需要什么，不按协议里有什么。状态词：**已实现**（有公开件且真桶跑过）、
**部分实现**（子集真桶跑过，其余只有离线件）、**待开发**（公开面里零命中）、
**不适用**（协议里没这一族）。

| 要的那一格 | 本 SDK 的件 | 状态 |
|---|---|---|
| 上传 / 下载 / 删除 / 存在 | `put_object` `get_object` `delete_object` `stat_object` | 已实现 |
| 用户元数据读写 | `metadata~`（`x-oss-meta-*`，写了能读回） | 已实现 |
| 单层列举 | `list_objects`（前缀／分隔符／续页） | 已实现 |
| 手动分片五步 | `create_multipart_upload` `upload_part` `list_parts` `complete_multipart_upload` `abort_multipart_upload` | 已实现 |
| 预签名 GET 与 PUT | `presigned_get_url` `presigned_put_url` | 已实现 |
| 同平台复制 | `copy_object`（移动＝复制＋`delete_object`） | 已实现 |
| 对象 ACL 读写 | `put_object_acl` `get_object_acl` | 已实现 |
| 服务级列桶 | `list_buckets` | 已实现 |
| 批量删除 | `delete_objects` | 已实现 |
| 对象标签三件 | `put_object_tagging` `get_object_tagging` `delete_object_tagging` | 已实现 |
| 分片复制／未完成分片 | `upload_part_copy` `list_multipart_uploads` | 已实现 |
| 条件请求（含复制源条件） | `if_match~` 等可选参数 | 已实现 |
| 自动 MD5 / CRC64 读回 | `compute_md5~` `content_md5~` `object_crc64` `crc64_xz` | 已实现 |
| 存储类写入与回读 | `storage_class~`；`ObjectInfo`/`ObjectStat.storage_class` | 已实现 |
| 追加写／归档解冻 | `append_object` `restore_object` | 部分实现（解冻仅离线件） |
| 表单上传 | `post_object`（V4 默认，V1 兼容） | 已实现 |
| 软链接 | `put_symlink` `get_symlink` | 已实现 |
| 桶基础 | `create_bucket` `delete_bucket` `bucket_exists` | 部分实现（建/删未跑真桶） |
| 桶配置读 | ACL／版本／CORS／标签／日志／网站／加密／生命周期／防盗链／策略／复制／清单／传输加速／自定义域／区域／桶信息／请求者付费／资源组 | 已实现 |
| 桶配置写 | 上述九族的 `put_*` / `delete_*` | 部分实现（只有离线件） |
| 大文件"一条式"上传（自动切分片） | `put_bytes_auto`（超阈值自动切分片，失败回收） | 已实现 |
| 上传进度回调／断点续传 | 无对应件（`put_bytes_auto` 只做自动切分片） | 待开发 |
| STS 临时凭据（`x-oss-security-token`） | `Credentials::with_security_token`（请求头；预签名暂不支持） | 部分实现 |

完整对标台账（官方基线、P0–P3、逐项证据）：[PARITY.md](PARITY.md)。

## 与 S3 客户端的分工

同一个桶既能被 `moon-s3`（走 S3 兼容层）打到也能被本仓打到，但结论不互借：兼容层的对象写入
是通的，实测只在 canned ACL 写那一格被桶策略拒过（403）；本仓全程走原生协议。
判"某个形状 OSS 认不认"，这里只认真桶读数。
