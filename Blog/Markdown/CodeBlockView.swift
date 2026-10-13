import SwiftUI

/// 代码块：不折行，横向滚动；长按 / 右键可以复制整段
struct CodeBlockView: View {
  let language: String?
  let code: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let language {
        Text(verbatim: language)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding([.top, .horizontal], 12)
      }
      ScrollView(.horizontal) {
        Text(verbatim: code)
          .font(Typography.code)
          .fixedSize(horizontal: true, vertical: false)
          .padding(12)
      }
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    // .continuous 是 SwiftUI 的连续曲率圆角（网站上用 corner-shape: squircle 模仿的就是它）
    .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
    .contextMenu {
      Button("Copy Code", systemImage: "doc.on.doc") { Pasteboard.copy(code) }
    }
  }
}
