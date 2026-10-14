import AuthenticationServices
import BlogKit
import Foundation
import Observation
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// 后台的登录状态。token 在钥匙串里；session 失效（过期、在别处退出）时任何接口都会回 401，那时回到未登录。
///
/// 各页面直接读 `session.client`，不另设一个环境值：AdminSession 从 App 的根部注入，任何页面都拿得到；
/// 而设在后台标签页 NavigationStack 上的环境值，在 macOS 的侧边栏 TabView 里推进去的页面拿不到
/// （iPhone 上拿得到），后台页面因此一直在转圈
@Observable
final class AdminSession {
  enum State {
    /// 有 token，正在向服务器确认它还有效
    case checking
    case signedOut
    case signedIn(SessionInfo)
    /// 有 token 但确认不了（离线、服务器出错）：先当作已登录，各页面自己报错
    case unverified(AdminAPIError)
  }

  private(set) var state: State
  private(set) var client: AdminClient?
  /// 刚才因为 session 失效而退出（提示"登录已过期"）
  private(set) var expired = false

  @ObservationIgnored private let apiBaseURL: URL
  @ObservationIgnored private let siteURL: URL

  init(apiBaseURL: URL = AppConfiguration.apiBaseURL, siteURL: URL = AppConfiguration.siteURL) {
    self.apiBaseURL = apiBaseURL
    self.siteURL = siteURL
    if let token = AppConfiguration.injectedAdminToken ?? TokenStore.load() {
      client = AdminClient(baseURL: apiBaseURL, token: token)
      state = .checking
    } else {
      state = .signedOut
    }
  }

  var isSignedIn: Bool {
    switch state {
    case .signedIn, .unverified, .checking: client != nil
    case .signedOut: false
    }
  }

  var displayName: String? {
    if case .signedIn(let info) = state { info.user.displayName } else { nil }
  }

  func verify() async {
    guard let client else { return }
    do {
      state = .signedIn(try await client.session())
    } catch where error.isUnauthorized {
      signOutLocally(expired: true)
    } catch where error.kind == .cancelled {
      return
    } catch {
      state = .unverified(error)
    }
  }

  enum SignInError: Error {
    case cancelled
    case denied
    case failed(String)

    var message: String? {
      switch self {
      case .cancelled: nil
      case .denied: "已在网页上取消。"
      case .failed(let message): message
      }
    }
  }

  /// 在系统的网页登录窗口（ASWebAuthenticationSession）里打开网站的授权页，拿到授权码后换 token
  func signIn(using authenticate: WebAuthenticationSession) async throws(SignInError) {
    let request = AppAuthRequest.make()
    let url = request.authorizeURL(site: siteURL, deviceName: Self.deviceName)
    let callback: URL
    do {
      // .shared：和 Safari 共用登录状态——网页上已经登录着的话，只需要点"允许"
      callback = try await authenticate.authenticate(
        using: url, callback: .customScheme(AppAuthRequest.callbackScheme), preferredBrowserSession: .shared, additionalHeaderFields: [:])
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      throw .cancelled
    } catch {
      throw .failed("无法打开登录页面：\(error.localizedDescription)")
    }
    let code: String
    do {
      code = try request.code(from: callback)
    } catch .denied {
      throw .denied
    } catch {
      throw .failed("登录结果无效，请重新登录。")
    }
    do {
      let token = try await AdminClient.exchange(baseURL: apiBaseURL, code: code, verifier: request.verifier)
      TokenStore.save(token.token)
      client = AdminClient(baseURL: apiBaseURL, token: token.token)
      expired = false
      state = .signedIn(token.session)
    } catch {
      throw .failed(error.message)
    }
  }

  /// 退出：先让服务器作废这个 session（失败也照样清掉本地的 token）
  func signOut() async {
    try? await client?.logout()
    signOutLocally(expired: false)
  }

  /// 页面上的请求出错时调用：401 说明 session 失效了
  func handle(_ error: AdminAPIError) {
    if error.isUnauthorized { signOutLocally(expired: true) }
  }

  private func signOutLocally(expired: Bool) {
    TokenStore.delete()
    client = nil
    self.expired = expired
    state = .signedOut
  }

  /// 授权页上显示的设备名（只用来提醒管理员，服务器不当作身份证明）
  static var deviceName: String {
    #if os(macOS)
      Host.current().localizedName ?? "Mac"
    #else
      // iOS 16 起没有专门的权限拿不到用户起的设备名，只有型号
      UIDevice.current.model
    #endif
  }
}
