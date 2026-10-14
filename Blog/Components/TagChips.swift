import BlogKit
import SwiftUI

/// 文章页的标签：可以换行的一排胶囊按钮，点了进标签页（网站上 TagSummary 的样子）
struct TagChips: View {
  let tags: [Tag]
  /// 正文的语言：标签没有这种语言的译名时显示原文名称，按名称自己的语言排版
  let contentLocale: ContentLocale

  var body: some View {
    FlowLayout(spacing: 8) {
      ForEach(tags) { tag in
        NavigationLink(value: Route.tag(slug: tag.slug, name: tag.name)) {
          Text(verbatim: "#" + tag.name)
            .typesettingLanguage(tag.locale.language)
            .font(.app(.subheadline).weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
      }
    }
  }
}

/// 从左到右排、放不下就换行
struct FlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    var y = bounds.minY
    for row in arrange(subviews, maxWidth: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > maxWidth, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}
