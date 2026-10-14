import BlogKit
import SwiftUI

/// 文章正文的版面：头图和"大"图出血（最宽 864，手机上贴边），其余内容在 680 的正文栏里
struct ArticleView: View {
  let article: Article
  let requestedLocale: ContentLocale
  let switchLocale: (ContentLocale) -> Void

  @Environment(\.blogClient) private var client
  @Environment(\.locale) private var locale
  @State private var views: Int?
  @State private var viewportHeight: CGFloat = 800

  private var post: PublicPost { article.post }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        if let cover = post.cover {
          coverImage(cover)
        }
        header
          .readingColumn()
        TranslationNotice(post: post, requestedLocale: requestedLocale, switchLocale: switchLocale)
          .readingColumn()
        body(article.document.blocks)
        if !post.tags.isEmpty {
          TagChips(tags: post.tags, contentLocale: post.locale)
            .readingColumn()
        }
        CommentsSection(post: post)
          .readingColumn()
      }
      .padding(.vertical, 24)
      // 正文、标题按文章的语言排版：中日共用汉字，靠语言选字形（网站上 <html lang> 的作用）
      .typesettingLanguage(post.locale.language)
      .environment(\.markdownImages, post.images)
      .environment(\.articleViewportHeight, viewportHeight)
      .textSelection(.enabled)
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    .task(id: post.slug) { views = try? await client.views(slug: post.slug) }
  }

  private func coverImage(_ cover: PostCover) -> some View {
    let ratio = cover.meta.map { CGFloat($0.width) / CGFloat($0.height) } ?? 16 / 9
    return RemoteImage(url: cover.url, meta: cover.meta)
      .aspectRatio(ratio, contentMode: .fit)
      .frame(maxWidth: min(ReadingLayout.bleedWidth, cover.width.map(CGFloat.init) ?? .infinity))
      .accessibilityLabel(cover.alt)
      .accessibilityHidden(cover.alt.isEmpty)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(post.title)
        .font(Typography.articleTitle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("article-title")
      HStack(spacing: 12) {
        Text(post.publishedAt, format: SiteCalendar.dateStyle(locale: locale))
        if let views {
          Label(views.formatted(), systemImage: "eye")
            .accessibilityLabel(Text("\(views) views"))
        }
      }
      .font(.app(.subheadline).weight(.semibold))
      .foregroundStyle(.secondary)
    }
  }

  /// 正文的块：单独成段的大图放在正文栏外，其他块在正文栏里
  private func body(_ blocks: [MarkdownBlock]) -> some View {
    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
      if case .figure(let image) = block {
        if image.maxDisplayWidth > ReadingLayout.readingWidth {
          FigureView(image: image)
            .frame(maxWidth: ReadingLayout.bleedWidth)
        } else {
          FigureView(image: image)
            .readingColumn()
        }
      } else {
        MarkdownBlockView(block: block)
          .readingColumn()
      }
    }
  }
}
