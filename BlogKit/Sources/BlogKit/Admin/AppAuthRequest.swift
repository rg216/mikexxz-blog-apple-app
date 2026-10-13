import CryptoKit
import Foundation

/// 一次"用浏览器登录后台"（RFC 8252 + PKCE，见网站 packages/shared 的 app-auth.ts）：
/// 生成 verifier 和 state，拼出网站授权页的地址，再从回跳地址里取出授权码
public struct AppAuthRequest: Sendable {
  /// 网站只接受这一个回跳地址（APP_AUTH_REDIRECT_URI）
  public static let redirectURI = "mikexxz-blog://auth/callback"
  public static let callbackScheme = "mikexxz-blog"

  /// PKCE code_verifier：只留在 App 里，换 token 时证明"发起登录的就是我"
  public let verifier: String
  /// 防止把别处发起的登录结果塞给这个 App（回跳时必须原样带回）
  public let state: String

  public init(verifier: String, state: String) {
    self.verifier = verifier
    self.state = state
  }

  /// 32 字节随机数的 base64url：43 个字符，正好是 RFC 7636 允许的最短长度
  public static func make() -> AppAuthRequest {
    AppAuthRequest(verifier: randomToken(bytes: 32), state: randomToken(bytes: 24))
  }

  /// S256：base64url(SHA-256(verifier))
  public var challenge: String {
    Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  public func authorizeURL(site: URL, deviceName: String) -> URL {
    var url = site.appending(path: "admin/authorize-app")
    url.append(queryItems: [
      URLQueryItem(name: "challenge", value: challenge),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "device", value: String(deviceName.prefix(60))),
      URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
    ])
    return url
  }

  public enum CallbackError: Error, Equatable, Sendable {
    /// 管理员在网站上点了"取消"
    case denied
    /// state 对不上、缺参数：不是这次登录的回跳
    case invalid
  }

  public func code(from callback: URL) throws(CallbackError) -> String {
    // mikexxz-blog://auth/callback：scheme、host、path 分别比较
    guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      components.scheme == Self.callbackScheme, components.host == "auth", components.path == "/callback"
    else { throw .invalid }
    let items = components.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    guard value("state") == state else { throw .invalid }
    if value("error") != nil { throw .denied }
    guard let code = value("code"), !code.isEmpty else { throw .invalid }
    return code
  }

  static func randomToken(bytes count: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    return base64url(Data(bytes))
  }

  static func base64url(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
