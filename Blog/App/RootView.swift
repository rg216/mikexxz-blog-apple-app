import BlogKit
import SwiftUI

enum AppTab: String, Hashable {
  case posts, tags, archive, admin, search
}

/// 顶层导航：iPhone 上是底部标签栏；iPad 和 Mac 上 `.sidebarAdaptable` 变成侧边栏（iPad 上读者可以切回标签栏）。
/// 搜索用 `role: .search` 的标签：iOS 上它单独放在标签栏右侧，Mac 侧边栏里放在顶部，都是系统约定的位置。
struct RootView: View {
  @SceneStorage("selectedTab") private var selection = AppTab.posts
  /*
   * Mac 的侧边栏 TabView 切走再切回来时，标签页里的 NavigationStack 会显示成第一页，可它的路径仍是原来的
   * （日志确认绑定的值没变）：界面和状态对不上，再点列表里的链接也没反应（2026-10 实测，iPhone 上没有这个问题）。
   * 绕过办法：路径放在一直都在的 RootView 里；Mac 上每次切回一个标签页就换一个 id 重建它的导航栈，
   * 新建的 NavigationStack 按路径还原，回来时停在原来的页面（代价是那一页重新加载一次数据）
   */
  @State private var postsPath: [Route] = []
  @State private var tagsPath: [Route] = []
  @State private var archivePath: [Route] = []
  @State private var searchPath: [Route] = []
  @State private var adminPath: [AdminRoute] = []
  @State private var visits: [AppTab: Int] = [:]

  var body: some View {
    TabView(selection: $selection) {
      Tab("Posts", systemImage: "doc.text.image", value: AppTab.posts) {
        RoutedStack(path: $postsPath) {
          PostFeedView(filter: PostFilter())
            .navigationTitle("Posts")
        }
        .id(visits[.posts, default: 0])
      }
      Tab("Tags", systemImage: "tag", value: AppTab.tags) {
        RoutedStack(path: $tagsPath) { TagsView() }
          .id(visits[.tags, default: 0])
      }
      Tab("Archive", systemImage: "archivebox", value: AppTab.archive) {
        RoutedStack(path: $archivePath) { ArchiveView() }
          .id(visits[.archive, default: 0])
      }
      // 后台：登录后管理文章、标签、评论、媒体库；不登录也能进，里面的"设置"放着文章语言
      Tab("Admin", systemImage: "person.crop.circle", value: AppTab.admin) {
        AdminHomeView(path: $adminPath)
          .id(visits[.admin, default: 0])
      }
      Tab(value: AppTab.search, role: .search) {
        RoutedStack(path: $searchPath) { SearchView() }
          .id(visits[.search, default: 0])
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    #if os(macOS)
      .onChange(of: selection) { _, tab in visits[tab, default: 0] += 1 }
    #endif
  }
}
