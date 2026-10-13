import BlogKit
import SwiftUI

/// 一次请求的状态
enum Loadable<Value> {
  case loading
  case loaded(Value)
  case failed(BlogAPIError)

  var value: Value? {
    if case .loaded(let value) = self { value } else { nil }
  }
}

extension BlogAPIError {
  /// 错误按原因显示本地化文案；API 的 message 是给后台看的中文，不直接给读者看
  var title: LocalizedStringResource {
    switch self {
    case .offline: "You're Offline"
    case .server(404, _): "Not Found"
    case .server(429, _): "Too Many Requests"
    case .server: "Server Unavailable"
    case .decoding: "Update Required"
    case .transport, .cancelled: "Couldn't Load"
    }
  }

  var message: LocalizedStringResource {
    switch self {
    case .offline: "Connect to the internet and try again."
    case .server(404, _): "This page doesn't exist or is no longer published."
    case .server(429, _): "Please wait a moment and try again."
    case .server: "The blog's server didn't respond properly. Try again later."
    case .decoding: "The blog has changed in a way this version of the app doesn't understand. Update the app from the App Store."
    case .transport, .cancelled: "Something went wrong. Try again."
    }
  }

  var systemImage: String {
    switch self {
    case .offline: "wifi.slash"
    case .server(404, _): "questionmark.text.page"
    case .decoding: "arrow.down.app"
    default: "exclamationmark.triangle"
    }
  }
}

/// 整页的错误状态：说明原因，能重试的给一个重试按钮
struct ErrorStateView: View {
  let error: BlogAPIError
  var retry: (() async -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(String(localized: error.title), systemImage: error.systemImage)
    } description: {
      Text(error.message)
    } actions: {
      if let retry, !error.isNotFound {
        Button("Try Again") { Task { await retry() } }
          .buttonStyle(.bordered)
      }
    }
  }
}
