import BlogKit
import SwiftUI

@main
struct BlogApp: App {
  @State private var settings = ReaderSettings()
  @State private var adminSession = AdminSession()
  private let client: BlogClient

  init() {
    // API 的 JSON 和 R2 上的图片都经过系统的 URLCache：图片带一年的 Cache-Control，
    // API 响应离线时退回这里的旧数据（见 BlogClient）。默认容量（内存 512KB）对图片太小
    URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20)
    client = BlogClient(baseURL: AppConfiguration.apiBaseURL)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(settings)
        .environment(adminSession)
        .environment(\.blogClient, client)
    }
    #if os(macOS)
      .defaultSize(width: 1100, height: 800)
    #endif

    #if os(macOS)
      // macOS 的偏好设置照平台惯例放在"设置"窗口（⌘,）；同样的选项也在"后台"标签页的"设置"里
      Settings {
        SettingsView()
          .environment(settings)
      }
    #endif
  }
}
