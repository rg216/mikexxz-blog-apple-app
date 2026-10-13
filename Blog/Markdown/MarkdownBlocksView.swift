import BlogKit
import SwiftUI

/// 文章和评论用的排版参数（评论字号小一号、段距更紧）
struct MarkdownTheme {
  var bodyFont: Font
  var lineSpacing: CGFloat
  var blockSpacing: CGFloat

  static let article = MarkdownTheme(bodyFont: Typography.articleBody, lineSpacing: 6, blockSpacing: 16)
  static let comment = MarkdownTheme(bodyFont: Typography.commentBody, lineSpacing: 3, blockSpacing: 8)
}

extension EnvironmentValues {
  @Entry var markdownTheme = MarkdownTheme.article
  /// 正文引用的媒体库图片的宽高和尺寸版本（PublicPost.images）
  @Entry var markdownImages: [String: ImageMeta] = [:]
  @Entry var markdownListDepth = 0
}

/// 一串块，竖着排
struct MarkdownBlocksView: View {
  let blocks: [MarkdownBlock]

  @Environment(\.markdownTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        MarkdownBlockView(block: block)
      }
    }
  }
}

struct MarkdownBlockView: View {
  let block: MarkdownBlock

  @Environment(\.markdownTheme) private var theme

  var body: some View {
    switch block {
    case .paragraph(let text):
      Text(text)
        .font(theme.bodyFont)
        .lineSpacing(theme.lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
    case .heading(let level, let text):
      Text(text)
        .font(Typography.heading(level))
        .padding(.top, level <= 2 ? 12 : 4)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHeading(level == 1 ? .h1 : level == 2 ? .h2 : level == 3 ? .h3 : .h4)
    case .figure(let image):
      FigureView(image: image)
    case .code(let language, let code):
      CodeBlockView(language: language, code: code)
    case .quote(let blocks):
      HStack(alignment: .top, spacing: 12) {
        Capsule()
          .fill(.tertiary)
          .frame(width: 3)
        MarkdownBlocksView(blocks: blocks)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
    case .list(let list):
      MarkdownListView(list: list)
    case .table(let table):
      MarkdownTableView(table: table)
    case .thematicBreak:
      Divider()
        .padding(.vertical, 8)
    case .html(let raw):
      Text(raw)
        .font(Typography.code)
        .foregroundStyle(.secondary)
    }
  }
}

struct MarkdownListView: View {
  let list: MarkdownList

  @Environment(\.markdownTheme) private var theme
  @Environment(\.markdownListDepth) private var depth

  var body: some View {
    VStack(alignment: .leading, spacing: theme.blockSpacing / 2) {
      ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          marker(index: index, item: item)
            .font(theme.bodyFont)
            .frame(minWidth: 20, alignment: .trailing)
          MarkdownBlocksView(blocks: item.blocks)
            .environment(\.markdownListDepth, depth + 1)
            .environment(\.markdownTheme, nested)
        }
      }
    }
  }

  /// 列表项里的段落挨得近一些
  private var nested: MarkdownTheme {
    var theme = theme
    theme.blockSpacing = theme.blockSpacing / 2
    return theme
  }

  @ViewBuilder private func marker(index: Int, item: MarkdownListItem) -> some View {
    if let checked = item.checkbox {
      Image(systemName: checked ? "checkmark.square.fill" : "square")
        .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .accessibilityLabel(checked ? Text("Completed") : Text("Not completed"))
    } else if list.ordered {
      Text(verbatim: "\(list.start + index).")
        .monospacedDigit()
        .foregroundStyle(.secondary)
    } else {
      Text(verbatim: ["•", "◦", "▪"][depth % 3])
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }
}
