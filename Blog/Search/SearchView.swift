import BlogKit
import SwiftUI

/// 搜索：关键词 + 标签。网站搜索页的标签筛选在这里是搜索框里的"令牌"（tokens），系统原生的做法：
/// 输入时下方建议匹配的标签，选中后成为搜索框里的一个标签令牌。
/// - 有关键词：全文搜索，按相关度取前 20 条（同时满足所选标签）
/// - 只有标签：按时间列出带这些标签的文章，可以一直往下翻
struct SearchView: View {
  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  @Environment(\.locale) private var locale
  @State private var query = ""
  @State private var tokens: [Tag] = []
  @State private var allTags: [TagWithCount] = []
  @State private var results: Loadable<[SearchHit]>?

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  private struct SearchKey: Hashable {
    let query: String
    let tags: [String]
    let locale: ContentLocale
  }

  var body: some View {
    content
      .navigationTitle("Search")
      .searchable(text: $query, tokens: $tokens, prompt: Text("Titles, tags and text")) { tag in
        Label(tag.name, systemImage: "tag")
      }
      .searchSuggestions {
        ForEach(suggestedTags) { tag in
          Label(tag.name, systemImage: "tag")
            .searchCompletion(tag.tag)
        }
      }
      .task(id: settings.contentLocale) {
        tokens = []
        allTags = (try? await client.tags(locale: settings.contentLocale)) ?? []
      }
      .task(id: SearchKey(query: trimmedQuery, tags: tokens.map(\.slug), locale: settings.contentLocale)) {
        await search()
      }
  }

  @ViewBuilder private var content: some View {
    if trimmedQuery.isEmpty && tokens.isEmpty {
      ContentUnavailableView(
        "Search Posts",
        systemImage: "magnifyingglass",
        description: Text("Search titles, tags and text in \(settings.contentLocale.name(in: locale)). Type a tag's name to filter by it.")
      )
    } else if trimmedQuery.isEmpty {
      PostFeedView(filter: PostFilter(tags: tokens.map(\.slug)))
    } else {
      switch results {
      case nil, .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let error):
        ErrorStateView(error: error) { await search(debounce: false) }
      case .loaded(let hits) where hits.isEmpty:
        ContentUnavailableView.search(text: trimmedQuery)
      case .loaded(let hits):
        List(hits) { hit in
          NavigationLink(value: Route.post(slug: hit.slug)) {
            SearchHitRow(hit: hit)
          }
        }
        #if os(iOS)
          .listStyle(.plain)
        #endif
      }
    }
  }

  /// 输入的文字匹配的标签（还没选的）；没输入时列出全部
  private var suggestedTags: [TagWithCount] {
    let selected = Set(tokens.map(\.slug))
    let available = allTags.filter { !selected.contains($0.slug) }
    guard !trimmedQuery.isEmpty else { return available }
    return available.filter { $0.name.localizedStandardContains(trimmedQuery) || $0.slug.contains(trimmedQuery.lowercased()) }
  }

  /// 防抖 250ms（和网站一样）：边打字边搜既浪费，也容易撞上按 IP 的限流
  private func search(debounce: Bool = true) async {
    guard !trimmedQuery.isEmpty else {
      results = nil
      return
    }
    if debounce {
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
    }
    if results?.value == nil { results = .loading }
    do {
      results = .loaded(try await client.search(trimmedQuery, locale: settings.contentLocale, filter: PostFilter(tags: tokens.map(\.slug))))
    } catch .cancelled {
      return
    } catch {
      results = .failed(error)
    }
  }
}

/// 搜索结果：命中的字加底色（网页上的 <mark>，Safari 页内查找也是这样）。只加粗的话，
/// 本来就是粗体的标题里看不出来。API 给的是高亮区间（UTF-16 下标），不是 HTML
struct SearchHitRow: View {
  let hit: SearchHit

  @Environment(\.locale) private var locale

  private static let highlight = AttributeContainer()
    .backgroundColor(Color.yellow.opacity(0.35))
    .foregroundColor(.primary)

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(hit.title.attributed(highlight: Self.highlight))
        .font(.headline)
      Text(hit.snippet.attributed(highlight: Self.highlight))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(4)
      Text(hit.publishedAt, format: SiteCalendar.dateStyle(locale: locale))
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .typesettingLanguage(hit.locale.language)
    .padding(.vertical, 6)
  }
}
