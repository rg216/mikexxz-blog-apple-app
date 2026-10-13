import BlogKit
import SwiftUI

/// 文章页：按读者选的语言请求；这一篇也可以单独换成别的语言（比如从机器译文切回原文）
struct PostDetailView: View {
  let slug: String

  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  /// 只对这一篇生效的语言；nil 表示跟随设置
  @State private var localeOverride: ContentLocale?
  @State private var state: Loadable<Article> = .loading

  private var requestedLocale: ContentLocale { localeOverride ?? settings.contentLocale }

  var body: some View {
    content
      .navigationTitle(state.value?.post.title ?? "")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar { toolbar }
      .task(id: requestedLocale) { await load() }
  }

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      ErrorStateView(error: error) { await load() }
    case .loaded(let article):
      ArticleView(article: article, requestedLocale: requestedLocale) { localeOverride = $0 }
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if let post = state.value?.post {
      ToolbarItem(placement: .primaryAction) {
        ShareLink(item: SiteLinks.postURL(slug: post.slug, locale: post.locale), subject: Text(post.title)) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
      if post.availableLocales.count > 1 {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Picker("Language of This Post", selection: Binding(get: { post.locale }, set: { localeOverride = $0 })) {
              ForEach(post.availableLocales) { locale in
                Group {
                  if locale == post.sourceLocale {
                    Text("\(locale.endonym) (Original)")
                  } else {
                    Text(verbatim: locale.endonym)
                  }
                }
                .tag(locale)
              }
            }
            .pickerStyle(.inline)
          } label: {
            Label("Language of This Post", systemImage: "character.bubble")
          }
          .help("Language of This Post")
        }
      }
    }
  }

  private func load() async {
    // 换语言时保留旧内容直到新内容到达，避免整页闪成转圈
    if state.value?.post.slug != slug { state = .loading }
    do {
      let post = try await client.post(slug: slug, locale: requestedLocale)
      state = .loaded(await Article.prepare(post))
    } catch .cancelled {
      return
    } catch {
      state = .failed(error)
    }
  }
}

/// 文章和解析好的正文。Markdown 在后台线程解析：正文最长 20 万字，放在主线程会卡住转场动画
struct Article {
  let post: PublicPost
  let document: MarkdownDocument

  @concurrent static func prepare(_ post: PublicPost) async -> Article {
    Article(post: post, document: MarkdownDocument(parsing: post.contentMd))
  }
}
