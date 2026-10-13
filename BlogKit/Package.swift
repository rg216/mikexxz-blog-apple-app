// swift-tools-version: 6.3
import PackageDescription

// 与界面无关的部分：接口模型、API 客户端、Markdown 解析、网址与日期规则。
// 单独成包是为了能在 macOS 上直接 `swift test`，不必启动模拟器。
let package = Package(
  name: "BlogKit",
  defaultLocalization: "en",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [.library(name: "BlogKit", targets: ["BlogKit"])],
  dependencies: [
    // Apple 维护的 Markdown 解析器（cmark-gfm 的 Swift 封装）；渲染成 SwiftUI 视图的部分自己写
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
  ],
  targets: [
    .target(
      name: "BlogKit",
      dependencies: [.product(name: "Markdown", package: "swift-markdown")],
    ),
    .testTarget(name: "BlogKitTests", dependencies: ["BlogKit"], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6],
)
