import BlogKit
import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Identifiable {
  case posts, tags, archive, admin, search

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .posts: "Posts"
    case .tags: "Tags"
    case .archive: "Archive"
    case .admin: "Admin"
    case .search: "Search"
    }
  }

  var systemImage: String {
    switch self {
    case .posts: "doc.text.image"
    case .tags: "tag"
    case .archive: "archivebox"
    case .admin: "person.crop.circle"
    case .search: "magnifyingglass"
    }
  }
}

/// 顶层导航。
///
/// - iPhone / iPad：TabView。iPhone 上是底部标签栏；iPad 上 `.sidebarAdaptable` 可以在标签栏和侧边栏之间切换。
///   搜索用 `role: .search` 的标签，放在系统约定的位置
/// - Mac：NavigationSplitView（侧边栏 + 详情），Mac 上的标准做法（邮件、备忘录）。不用 TabView：
///   Mac 的 TabView 侧边栏里各标签页共用同一个导航栏（NavigationColumnState），每个标签页一个 NavigationStack 会互相打架——
///   切回来显示第一页而路径还在、之后点链接没反应；导航路径类型不同时 SwiftUI 内部的 try! 直接崩溃
///   （AnyNavigationPath.Error.comparisonTypeMismatch）。2026-10 实测
///
/// 每个栏目的导航路径都放在这里（RootView 一直都在），切换栏目再回来，还停在原来的页面
struct RootView: View {
  @SceneStorage("selectedTab") private var selection = AppTab.posts
  @State private var paths: [AppTab: NavigationPath] = [:]

  var body: some View {
    #if os(macOS)
      NavigationSplitView {
        List(selection: Binding<AppTab?>(get: { selection }, set: { if let tab = $0 { selection = tab } })) {
          ForEach(AppTab.allCases) { tab in
            Label(tab.title, systemImage: tab.systemImage).tag(tab)
          }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 190)
      } detail: {
        // 换栏目就换一个全新的导航栈（id），按这个栏目保存的路径还原
        content(for: selection)
          .id(selection)
      }
    #else
      TabView(selection: $selection) {
        Tab("Posts", systemImage: "doc.text.image", value: AppTab.posts) { content(for: .posts) }
        Tab("Tags", systemImage: "tag", value: AppTab.tags) { content(for: .tags) }
        Tab("Archive", systemImage: "archivebox", value: AppTab.archive) { content(for: .archive) }
        // 后台：登录后管理文章、标签、评论、媒体库；不登录也能进，里面的"设置"放着文章语言
        Tab("Admin", systemImage: "person.crop.circle", value: AppTab.admin) { content(for: .admin) }
        Tab(value: AppTab.search, role: .search) { content(for: .search) }
      }
      .tabViewStyle(.sidebarAdaptable)
    #endif
  }

  private func path(for tab: AppTab) -> Binding<NavigationPath> {
    Binding(
      get: { paths[tab] ?? NavigationPath() },
      set: { newPath in
        // 换栏目时，被换下去的导航栈在销毁前会把自己的路径清空（日志：posts 1 → 0 发生在切到后台之后）。
        // 那时选中的已经是别的栏目了：只接受当前栏目的修改，回来才能还原
        guard tab == selection else { return }
        paths[tab] = newPath
      })
  }

  @ViewBuilder private func content(for tab: AppTab) -> some View {
    switch tab {
    case .posts:
      RoutedStack(path: path(for: .posts)) {
        PostFeedView(filter: PostFilter())
          .navigationTitle("Posts")
      }
    case .tags:
      RoutedStack(path: path(for: .tags)) { TagsView() }
    case .archive:
      RoutedStack(path: path(for: .archive)) { ArchiveView() }
    case .admin:
      AdminHomeView(path: path(for: .admin))
    case .search:
      RoutedStack(path: path(for: .search)) { SearchView() }
    }
  }
}
