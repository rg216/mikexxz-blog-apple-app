import BlogKit
import SwiftUI

enum AppTab: String, Hashable {
  case posts, tags, archive, admin, search
}

/// 顶层导航：iPhone 上是底部标签栏；iPad 和 Mac 上 `.sidebarAdaptable` 变成侧边栏（iPad 上读者可以切回标签栏）。
/// 搜索用 `role: .search` 的标签：iOS 上它单独放在标签栏右侧，Mac 侧边栏里放在顶部，都是系统约定的位置。
struct RootView: View {
  @SceneStorage("selectedTab") private var selection = AppTab.posts

  var body: some View {
    TabView(selection: $selection) {
      Tab("Posts", systemImage: "doc.text.image", value: AppTab.posts) {
        RoutedStack {
          PostFeedView(filter: PostFilter())
            .navigationTitle("Posts")
        }
      }
      Tab("Tags", systemImage: "tag", value: AppTab.tags) {
        RoutedStack { TagsView() }
      }
      Tab("Archive", systemImage: "archivebox", value: AppTab.archive) {
        RoutedStack { ArchiveView() }
      }
      // 后台：登录后管理文章、标签、评论、媒体库；不登录也能进，里面的"设置"放着文章语言
      Tab("Admin", systemImage: "person.crop.circle", value: AppTab.admin) {
        AdminHomeView()
      }
      Tab(value: AppTab.search, role: .search) {
        RoutedStack { SearchView() }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}
