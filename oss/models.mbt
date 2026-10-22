///|
/// 对象族的读数形状。刻意做窄：只带这条线（文件存储契约）真要用的字段——
/// `etag`／`size`／`last_modified`／`content_type`／`metadata`。
/// OSS 响应头还有二十几项，全抄进来就等于承诺维护一份与协议同宽的面。

///|
pub(all) struct PutObjectResult {
  etag : String
}

///|
pub(all) struct ObjectData {
  content_length : Int64
  content_type : String?
  /// 只回 `x-oss-meta-*` 那几项（键名已去掉前缀），与 `metadata~` 入参同一坐标系
  metadata : Array[(String, String)]
  content_range : String?
  etag : String?
  /// 正文已整段读回。范围档与流式档共用这一格，因为调用方是要 bytes 的
  body : Bytes
}

///|
pub(all) struct ObjectInfo {
  key : String
  etag : String?
  size : Int64
  last_modified : String?
  storage_class : String?
}

///|
/// `HEAD /<key>` 的读数。与列举行那一格 `ObjectInfo` 分开定：这一族要带元数据与
/// content-type，而列举回包里根本没有它们。
pub(all) struct ObjectStat {
  key : String
  etag : String?
  size : Int64
  last_modified : String?
  content_type : String?
  storage_class : String?
  /// 只回 `x-oss-meta-*` 那几项（键名已去掉前缀），与 `metadata~` 入参同一坐标系
  metadata : Array[(String, String)]
}

///|
pub(all) struct ObjectListing {
  objects : Array[ObjectInfo]
  /// `delimiter` 折叠出来的"目录"，与 objects 同一次回包、同一坐标系
  common_prefixes : Array[String]
  is_truncated : Bool
  next_continuation_token : String?
  /// 回包原文。解析件只取简单形状，读不出的形状要能回查
  body : String
}

///|
pub(all) struct CopyResult {
  etag : String
  body : String
}

///|
/// 批量删除里单条失败。OSS 的 `<Error>` 与 `<Deleted>` 是同一层的兄弟节点，
/// 所以成功键与失败键分开收，不拿“发的键数减成功数”去猜失败原因。
pub(all) struct DeleteObjectFailure {
  key : String
  code : String
  message : String
}

///|
/// `POST /?delete` 的读数。`body` 保留原文，便于回查服务端多给的字段。
/// `quiet=true` 时服务端可以不回正文，此时两个数组都为空。
pub(all) struct DeleteObjectsResult {
  deleted : Array[String]
  errors : Array[DeleteObjectFailure]
  body : String
}

///|
/// `UploadPartCopy` 的读数。ETag 优先取 XML 里的那一格；回包没有 XML 时才退回响应头。
pub(all) struct UploadPartCopyResult {
  etag : String
  last_modified : String?
  body : String
}

///|
/// 一条未完成的分片任务。`upload_id` 是后续 abort/list parts 的入口。
pub(all) struct MultipartUploadInfo {
  key : String
  upload_id : String
  initiated : String?
}

///|
/// `GET /?uploads` 的一页。`next_*` 为空表示没有下一页。
pub(all) struct MultipartUploadListing {
  uploads : Array[MultipartUploadInfo]
  common_prefixes : Array[String]
  is_truncated : Bool
  next_key_marker : String?
  next_upload_id_marker : String?
  body : String
}

///|
/// 对象标签的一对键值。OSS 上限 10 对，键在对象内唯一。
pub(all) struct ObjectTag {
  key : String
  value : String
}

///|
/// `GET /<key>?tagging` 的读数。`body` 保留原文，空标签时两个数组都为空。
pub(all) struct ObjectTagging {
  tags : Array[ObjectTag]
  body : String
}

///|
/// `POST /` 表单上传的读数。`success_action_status=204` 时正文为空，`etag` 来自响应头；
/// 201 时正文是 XML，`etag`/`location`/`key` 从 XML 补。
pub(all) struct PostObjectResult {
  status : Int32
  etag : String?
  location : String?
  key : String?
  body : String
}

///|
/// `POST /<key>?append&position=N` 的读数。`next_position` 来自服务端头，
/// 缺头时为 `None`，不拿本次 `position + data.length()` 猜。
pub(all) struct AppendResult {
  next_position : Int64?
  etag : String?
  body : String
}
