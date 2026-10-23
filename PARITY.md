# moon-oss · 官方 OSS SDK 对标台账

> 协议基线：[OSS API 参考](https://help.aliyun.com/zh/oss/developer-reference/)
> 参考实现：`aliyun/alibabacloud-oss-go-sdk-v2@v1.6.1`（2026-10-16）；交叉核对 Java `3.18.5`（2026-01-30）
> 本仓版本：`mldong/moon-oss@0.18.0`
> 当前公开面：81 个 `Client::` 方法（0.18.0）
> 状态：现有行先记 `已实现`，真桶证据待按基线逐行复核

## 1. 当前公开面

| ID | 能力族 | 官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|---|
| OSS-OBJ-001 | 对象 CRUD | PutObject / GetObject / HeadObject / DeleteObject / PutObjectCopy | `put_object` `get_object` `stat_object` `delete_object` `copy_object` | P0 | 真桶已验证 | `oss/live_test.mbt`、`oss/live_object_test.mbt`（2026-10-22 真桶绿） |
| OSS-OBJ-002 | 列举 | GetBucketV2（ListObjectsV2） | `list_objects` | P0 | 真桶已验证 | `oss/live_test.mbt`（2026-10-22 真桶绿） |
| OSS-OBJ-003 | 批量删除 | DeleteObjects | `delete_objects` | P0 | 真桶已验证 | `oss/delete_ops_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 真桶绿） |
| OSS-OBJ-004 | 表单上传（扩展） | PostObject | `post_object`（V4 默认，V1 兼容） | P3 | 真桶已验证 | 官方 Go V2 SDK 未暴露 PostObject；本仓作为浏览器表单扩展实现，V4 与 V1 均真桶绿（2026-10-22） |
| OSS-OBJ-005 | 对象标签 | Put/Get/DeleteObjectTagging | `put_object_tagging` `get_object_tagging` `delete_object_tagging` | P0 | 真桶已验证 | `oss/tagging_ops_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 真桶绿） |
| OSS-OBJ-007 | 条件请求 | If-Match/If-None-Match + If-Modified-Since/If-Unmodified-Since + 复制源条件 | `put_object` `get_object` `stat_object` `delete_object` `copy_object` `upload_part_copy` 的可选参数 | P0 | 真桶已验证 | `oss/object_options_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 真桶绿） |
| OSS-OBJ-013 | 校验和 | CRC64 读回（`x-oss-hash-crc64ecma`） | `crc64_xz` `crc64_decimal` `object_crc64` | P0 | 真桶已验证 | `oss/checksum_ops_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 与真桶头逐位相同） |
| OSS-MPU-001 | 分片 | Initiate / UploadPart / ListParts / Complete / Abort | `create_multipart_upload` `upload_part` `list_parts` `complete_multipart_upload` `abort_multipart_upload` | P0 | 真桶已验证 | `oss/live_test.mbt`（2026-10-22 真桶绿） |
| OSS-MPU-002 | 分片复制 | UploadPartCopy | `upload_part_copy` | P0 | 真桶已验证 | `oss/multipart_extra_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 真桶绿） |
| OSS-MPU-003 | 未完成分片 | ListMultipartUploads | `list_multipart_uploads` | P0 | 真桶已验证 | `oss/multipart_extra_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 真桶绿） |
| OSS-PRE-001 | 预签名 | 查询串 V4 签名（GET/PUT） | `presigned_get_url` `presigned_put_url` | P0 | 真桶已验证 | `oss/live_test.mbt`（2026-10-22 真桶绿） |
| OSS-ACL-001 | 对象 ACL | GetObjectACL / PutObjectACL | `get_object_acl` `put_object_acl` | P0 | 真桶已验证 | `oss/live_test.mbt`（2026-10-22 真桶绿）；canned 三档 |
| OSS-BKT-001 | 服务级列举 | ListBuckets | `list_buckets` | P1 | 真桶已验证 | `oss/live_test.mbt`（2026-10-22 真桶绿） |
| OSS-BKT-002 | 桶基础 | PutBucket / DeleteBucket / HeadBucket | `create_bucket` `delete_bucket` `bucket_exists` | P1 | 已实现 | `oss/bucket_admin_wbtest.mbt`；`bucket_exists` 2026-10-22 真桶绿；建/删桶不跑真桶 |
| OSS-BKT-003 | 桶 ACL | GetBucketACL / PutBucketACL | `get_bucket_acl` `put_bucket_acl` | P1 | 已实现 | `oss/acl_ops.mbt` 复用对象 ACL 解析；GET 2026-10-22 真桶绿，PUT 未跑 |
| OSS-BKT-005 | 版本控制 | GetBucketVersioning / PutBucketVersioning | `get_bucket_versioning` `put_bucket_versioning` | P1 | 已实现 | `oss/versioning_ops_wbtest.mbt`；GET 2026-10-22 真桶绿，PUT 未跑 |
| OSS-OBJ-012 | 归档解冻 | RestoreObject | `restore_object` | P1 | 已实现 | `oss/restore_ops_wbtest.mbt`；真桶待补（需归档对象） |
| OSS-BKT-004 | CORS | Get/Put/DeleteBucketCORS | `get_bucket_cors` `put_bucket_cors` `delete_bucket_cors` | P1 | 已实现 | `oss/cors_ops_wbtest.mbt`；GET 2026-10-22 真桶绿（无配置回空），PUT/DELETE 未跑 |

## 2. 缺口台账

### P0 · 数据面核心

| ID | 官方操作 | 我们的方法 | 状态 | 备注 |
|---|---|---|---|---|
| OSS-OBJ-006 | x-oss-storage-class（存储类） | 写入 `put_object`/`copy_object`/`create_multipart_upload`；回读 `stat_object`/`list_objects` | 真桶已验证 | 2026-10-22 真桶绿；`ObjectStat`/`ObjectInfo` 已加 `storage_class` 字段，需抬版本 |
| OSS-OBJ-008 | Content-MD5 / CRC64 | `put_object` / `upload_part` 已收 `content_md5~` 或 `compute_md5~` | 实现中 | 自动 MD5 2026-10-22 真桶绿；CRC64 未公开 |

### P1 · 控制面与厂商数据面扩展

| ID | 能力/官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|
| OSS-OBJ-009 | 追加写（AppendObject） | `append_object` | P1 | 真桶已验证 | `oss/append_ops_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22） |
| OSS-OBJ-010 | 软链接（Put/GetSymlink） | `put_symlink` `get_symlink` | P1 | 真桶已验证 | `oss/symlink_ops_wbtest.mbt`、`oss/live_extra_test.mbt`（2026-10-22 建链读目标、经链接取回正文） |
| OSS-OBJ-011 | 对象内查询（SelectObject） | `select_object_csv` `select_object_csv_records` `select_records` | P1 | 部分真桶 | 真桶事件流已解出 Records（按片拼接，CRC 跳过）；JSON 输入与 CRC 校验未做 |
| OSS-BKT-006 | 桶标签（Get/Put/DeleteBucketTagging） | `get_bucket_tagging` `put_bucket_tagging` `delete_bucket_tagging` | P1 | 已实现 | GET 2026-10-22 真桶绿；PUT/DELETE 未跑 |
| OSS-BKT-007 | 桶日志（Get/Put/DeleteBucketLogging） | `get_bucket_logging` `put_bucket_logging` `delete_bucket_logging` | P1 | 已实现 | GET 2026-10-22 真桶绿；PUT/DELETE 未跑 |
| OSS-BKT-008 | 生命周期（Get/Put/DeleteBucketLifecycle） | `get_bucket_lifecycle` `put_bucket_lifecycle` `delete_bucket_lifecycle` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（1 条规则）；写只落离线件 |
| OSS-BKT-015 | 防盗链（Referer） | `get_bucket_referer` `put_bucket_referer` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（白名单 0 条）；写入未跑 |
| OSS-BKT-013 | 网站托管（Get/Put/DeleteBucketWebsite） | `get_bucket_website` `put_bucket_website` `delete_bucket_website` | P1 | 已实现 | GET 2026-10-22 真桶绿；PUT/DELETE 未跑 |
| OSS-BKT-009 | 复制（Get/Put/DeleteBucketReplication） | `get_bucket_replication` `put_bucket_replication` `delete_bucket_replication` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（未配置回 None）；写只落离线件 |
| OSS-BKT-017 | 清单（Inventory 四件） | `put_bucket_inventory` `get_bucket_inventory` `delete_bucket_inventory` `list_bucket_inventories` | P1 | 部分真桶 | 真桶 list 空表 404 落空数组、缺失 id 回 None；写只落离线件 |
| OSS-BKT-014 | 服务端加密（Get/Put/DeleteBucketEncryption） | `get_bucket_encryption` `put_bucket_encryption` `delete_bucket_encryption` | P1 | 已实现 | GET 2026-10-22 真桶绿；PUT/DELETE 未跑 |
| OSS-BKT-010 | 桶策略（Get/Put/DeleteBucketPolicy） | `get_bucket_policy` `put_bucket_policy` `delete_bucket_policy` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（未配置回 None）；写只落离线件 |
| OSS-BKT-016 | 对象锁（Object Lock） | — | P1 | 不纳入 | 官方 Go V2 基线无 Object Lock API（走 WORM 另一族） |
| OSS-BKT-011 | 传输加速（Get/PutBucketTransferAcceleration） | `get_bucket_transfer_acceleration` `put_bucket_transfer_acceleration` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（未配置回 None）；写只落离线件 |
| OSS-BKT-018 | 自定义域（List/Put/DeleteCname） | `list_bucket_cnames` `put_bucket_cname` `delete_bucket_cname` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（1 条 CNAME）；写只落离线件 |
| OSS-BKT-019 | 资源组（Get/PutBucketResourceGroup） | `get_bucket_resource_group` `put_bucket_resource_group` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（rg-acfmw…）；写只落离线件 |
| OSS-BKT-012 | 区域/桶信息/请求者付费（Location/Info/RequestPayment） | `get_bucket_location` `get_bucket_info` `get_bucket_request_payment` `put_bucket_request_payment` | P1 | 部分真桶 | 三项读 2026-10-22 真桶绿（location/region=oss-cn-zhangjiakou、payer=BucketOwner）；写只落离线件 |
| OSS-BKT-020 | QoS | — | P1 | 不纳入 | 官方 Go V2 基线无 QoS 方法 |

### P2 · 便利/安全层

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| OSS-SEC-001 | STS 临时凭据（`x-oss-security-token`） | 部分实现 | 请求头 + 预签名查询串（`security-token`）都已接；缺 STS 凭据未真桶 |
| OSS-CNV-001 | 自动分片 + 进度 + 断点续传 | `put_bytes_auto` `put_bytes_resumable`（可外部持久化的分片状态） | 部分真桶 | 2026-10-24 真桶绿（先传第一片再带状态续完）；TransferManager 整体未做 |
| OSS-CNV-002 | TransferManager / 分页器 / 重试策略 | 部分实现 | `list_all_objects` 翻页器已落并真桶绿；进度回调/断点续传未做，重试是操作级重发 |

### P3 · 可选模块

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| OSS-EXT-001 | 图片处理（`x-oss-process` image/style） | 未开始 | 独立扩展模块 |
| OSS-EXT-002 | LiveChannel | 未开始 | 独立产品线 |
| OSS-EXT-003 | Vectors / Tables / AI VibeFlow | 未开始 | 独立产品线，不计入存储 SDK |

## 3. 不适用/边界

| 项 | 结论 | 理由 |
|---|---|---|
| Path-style 寻址 | 不适用 | OSS 仅收 virtual-hosted；真桶实测 path 一律 403 |
| 细粒度 ACL grant | 待复核 | 官方 S3 兼容表只列三档 canned ACL；原生 grant 面按基线再确认 |
| 桶创建/删除 | 纳入 P1，但不对 file-storage 门面开放 | 账号级动作，误用代价高 |
| README 的 S3 写入侧表述 | 需修正 | `moon-oss/README.md:7`、`:90` 写“S3 兼容层写入侧会被授权层拒”；阶段 G §1 实测是对象写入通、仅 canned ACL 写 403 |

## 4. 下一批

1. 现有 22 法真桶已复核（2026-10-22）；`post_object` 已补 V4 表单签名（`x-oss-signature-version` 那一族）并真桶绿，V1 仍可用。
2. 存储类回读：`ObjectStat`/`ObjectInfo` 加 `storage_class` 字段需拍公开结构变更与版本号。
3. 校验和：自动 MD5 与 CRC64 读回都已接；CRC64 实测是 CRC-64/XZ 变体（不是非反射 ECMA-182），实现与真桶头逐位相同。
4. P0 清完后开 P1 桶控制面；破坏性操作先写安全边界再写实现。
