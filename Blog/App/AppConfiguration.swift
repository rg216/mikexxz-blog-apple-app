import BlogKit
import Foundation
import SwiftUI

enum AppConfiguration {
  /// 默认连线上的 API。本地开发时在 scheme 的环境变量里设 `BLOG_API_URL=http://localhost:8787`
  /// （模拟器和 Mac 能访问本机；真机不行）。只在从 Xcode 启动时生效，装好的 App 总是连线上
  static var apiBaseURL: URL {
    if let value = ProcessInfo.processInfo.environment["BLOG_API_URL"], let url = URL(string: value), url.scheme != nil {
      return url
    }
    return BlogClient.productionURL
  }
}

extension EnvironmentValues {
  @Entry var blogClient = BlogClient()
}
