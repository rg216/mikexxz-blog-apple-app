import Foundation

/// API 的错误码（网站 `apiErrorCodeSchema`）；不认识的码保留原值
public struct APIErrorCode: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let validationError = APIErrorCode(rawValue: "validation_error")
  public static let notFound = APIErrorCode(rawValue: "not_found")
  public static let rateLimited = APIErrorCode(rawValue: "rate_limited")
  public static let internalError = APIErrorCode(rawValue: "internal_error")
}

public enum BlogAPIError: Error, Hashable, Sendable {
  /// 服务器返回了非 2xx；code 取自错误体，没有错误体（比如代理的 502 页面）时为 nil
  case server(status: Int, code: APIErrorCode?)
  /// 没有网络，也没有可用的缓存
  case offline
  /// 响应的形状和模型对不上（多半是 API 改了字段，App 还没更新）
  case decoding(String)
  case transport(String)
  /// 视图消失、搜索词变了等主动取消；界面上不当成错误显示
  case cancelled

  public var isNotFound: Bool {
    if case .server(404, _) = self { true } else { false }
  }

  public var isRateLimited: Bool {
    if case .server(429, _) = self { true } else { false }
  }
}
