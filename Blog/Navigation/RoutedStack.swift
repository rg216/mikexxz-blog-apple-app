import BlogKit
import SwiftUI

/// App 内可以前往的页面。文章只用 slug 定位（和公开接口一致），语言取读者的设置
enum Route: Hashable {
  case post(slug: String)
  /// name 未知（从正文里的链接进来）时为 nil，页面自己去查
  case tag(slug: String, name: String?)

  init(_ route: SiteRoute) {
    switch route {
    case .post(let slug): self = .post(slug: slug)
    case .tag(let slug): self = .tag(slug: slug, name: nil)
    }
  }

  @ViewBuilder var destination: some View {
    switch self {
    case .post(let slug): PostDetailView(slug: slug)
    case .tag(let slug, let name): TagPostsView(slug: slug, name: name)
    }
  }
}

/// 每个标签页各有一条导航栈。正文里指向本站文章、标签页的链接在栈里打开，不跳去浏览器
struct RoutedStack<Root: View>: View {
  @State private var path: [Route] = []
  private let root: Root

  init(@ViewBuilder root: () -> Root) {
    self.root = root()
  }

  var body: some View {
    NavigationStack(path: $path) {
      root.navigationDestination(for: Route.self) { $0.destination }
    }
    .environment(
      \.openURL,
      OpenURLAction { url in
        guard let route = SiteLinks.route(for: url) else { return .systemAction }
        path.append(Route(route))
        return .handled
      })
  }
}

extension View {
  /// 明确要在浏览器里打开的链接（比如"在网页上评论"）：绕过 RoutedStack 对站内链接的拦截
  func opensLinksInBrowser() -> some View {
    environment(\.openURL, OpenURLAction { _ in .systemAction })
  }
}
