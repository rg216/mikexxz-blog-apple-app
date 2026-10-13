import BlogKit
import SwiftUI

enum AppTab: String, Hashable {
  case posts, tags, archive, search
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
            .toolbar { ContentLanguageMenu() }
        }
      }
      Tab("Tags", systemImage: "tag", value: AppTab.tags) {
        RoutedStack { TagsView() }
      }
      Tab("Archive", systemImage: "archivebox", value: AppTab.archive) {
        RoutedStack { ArchiveView() }
      }
      Tab(value: AppTab.search, role: .search) {
        RoutedStack { SearchView() }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
  }
}
