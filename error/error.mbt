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
