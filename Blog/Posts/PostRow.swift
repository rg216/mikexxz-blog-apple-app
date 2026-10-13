import BlogKit
import SwiftUI

/// 列表里的一篇文章：标题、摘要、日期和标签，有头图时右侧放 4:3 缩略图（和网站的列表卡片一样）
struct PostRow: View {
  let post: PostSummary

  @Environment(\.locale) private var locale
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text(post.title)
          .font(.headline)
        Text(post.excerpt)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(3)
        meta
      }
      .typesettingLanguage(post.locale.language)
      .frame(maxWidth: .infinity, alignment: .leading)

      // 字号特别大时缩略图挤占文字，不显示（它是装饰性的）
      if let cover = post.cover, !dynamicTypeSize.isAccessibilitySize {
        RemoteImage(url: cover.url, meta: cover.meta, contentMode: .fill)
          .frame(width: 96, height: 72)
          .clipShape(.rect(cornerRadius: 8, style: .continuous))
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 6)
  }

  /// 小号灰字用 semibold 补偿（设计规范）。日期和标签拼成一段文字：分成两个视图并排时，
  /// 标签长了会把日期挤成两行；一段文字则自然折行
  private var meta: some View {
    let date = Text(post.publishedAt, format: SiteCalendar.dateStyle(locale: locale))
    // 不用 ListFormatStyle：中文的 .and 是"关于本站和全栈"，读起来像一个标签
    let tags = post.tags.map(\.name).joined(separator: String(localized: "tag-list-separator", defaultValue: ", "))
    return Group {
      if post.tags.isEmpty {
        date
      } else {
        Text("\(date) · \(tags)")
      }
    }
    .font(.footnote.weight(.semibold))
    .foregroundStyle(.secondary)
    .lineLimit(2)
  }
}
