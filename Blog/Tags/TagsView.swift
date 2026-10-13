import BlogKit
import SwiftUI

/// 标签总览：当前语言下有文章的标签和文章数（同一份数据也是网站侧栏的标签统计）
struct TagsView: View {
  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  @State private var state: Loadable<[TagWithCount]> = .loading

  var body: some View {
    content
      .navigationTitle("Tags")
      .task(id: settings.contentLocale) { await load() }
  }

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      ErrorStateView(error: error) { await load() }
    case .loaded(let tags) where tags.isEmpty:
      ContentUnavailableView("No Tags", systemImage: "tag")
    case .loaded(let tags):
      List(tags) { tag in
        NavigationLink(value: Route.tag(slug: tag.slug, name: tag.name)) {
          LabeledContent {
            Text(tag.count.formatted())
              .monospacedDigit()
          } label: {
            Text(tag.name)
              .typesettingLanguage(tag.locale.language)
          }
        }
      }
      .refreshable { await load() }
    }
  }

  private func load() async {
    do {
      state = .loaded(try await client.tags(locale: settings.contentLocale))
    } catch .cancelled {
      return
    } catch {
      if state.value == nil { state = .failed(error) }
    }
  }
}

/// 一个标签下的文章。从正文链接进来时不知道标签名，先用 slug 当标题，再从标签列表里查
struct TagPostsView: View {
  let slug: String
  let name: String?

  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  @State private var resolvedName: String?

  var body: some View {
    PostFeedView(filter: PostFilter(tags: [slug]))
      .navigationTitle(resolvedName ?? name ?? slug)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          ShareLink(item: SiteLinks.tagURL(slug: slug, locale: settings.contentLocale)) {
            Label("Share", systemImage: "square.and.arrow.up")
          }
        }
      }
      .task(id: settings.contentLocale) {
        // 切换语言后标签名也换成该语言的译名
        let tags = try? await client.tags(locale: settings.contentLocale)
        if let tag = tags?.first(where: { $0.slug == slug }) { resolvedName = tag.name }
      }
  }
}
