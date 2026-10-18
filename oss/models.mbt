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
