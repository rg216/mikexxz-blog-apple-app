import BlogKit
import SwiftUI

/// 表格：列宽按内容，放不下就横向滚动
struct MarkdownTableView: View {
  let table: MarkdownTable

  @Environment(\.markdownTheme) private var theme

  var body: some View {
    ScrollView(.horizontal) {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow {
          ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
            Text(cell)
              .fontWeight(.semibold)
              .gridColumnAlignment(alignment(column))
          }
        }
        Divider()
        ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
          GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
              Text(cell)
            }
          }
          if index < table.rows.count - 1 {
            Divider()
          }
        }
      }
      .font(theme.bodyFont)
      .padding(.vertical, 4)
    }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
  }

  private func alignment(_ column: Int) -> HorizontalAlignment {
    switch column < table.alignments.count ? table.alignments[column] : .leading {
    case .leading: .leading
    case .center: .center
    case .trailing: .trailing
    }
  }
}
