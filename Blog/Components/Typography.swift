import SwiftUI

/// 阅读排版。界面部分一律用系统文本样式；文章正文另有规则：
/// - iOS / iPadOS 用 Dynamic Type 的文本样式（正文 17pt，随读者的字号设置缩放）
/// - macOS 的 .body 只有 13pt，适合控件不适合长文；按网站的阅读字号（正文 17、标题 34）给固定大小
enum Typography {
  static var articleTitle: Font {
    #if os(macOS)
      .system(size: 34, weight: .bold)
    #else
      .largeTitle.bold()
    #endif
  }

  static var articleBody: Font {
    #if os(macOS)
      .system(size: 17)
    #else
      .body
    #endif
  }

  static var commentBody: Font {
    #if os(macOS)
      .system(size: 14)
    #else
      .callout
    #endif
  }

  static var code: Font {
    #if os(macOS)
      .system(size: 14, design: .monospaced)
    #else
      .system(.callout, design: .monospaced)
    #endif
  }

  /// 正文里的标题：h2 和网站一样是 22pt 粗体（Title 2）
  static func heading(_ level: Int) -> Font {
    #if os(macOS)
      switch level {
      case 1: .system(size: 28, weight: .bold)
      case 2: .system(size: 22, weight: .bold)
      case 3: .system(size: 20, weight: .semibold)
      default: .system(size: 17, weight: .semibold)
      }
    #else
      switch level {
      case 1: .title.bold()
      case 2: .title2.bold()
      case 3: .title3.weight(.semibold)
      default: .headline
      }
    #endif
  }
}

/// 版面宽度（与网站的三层宽度一致）
enum ReadingLayout {
  /// 正文栏
  static let readingWidth: CGFloat = 680
  /// 出血图片、头图
  static let bleedWidth: CGFloat = 864
  /// 正文左右留白（手机上）
  static let readingMargin: CGFloat = 20
}

extension View {
  /// 正文栏：最宽 680，手机上两侧留白，宽屏上居中
  func readingColumn() -> some View {
    frame(maxWidth: ReadingLayout.readingWidth, alignment: .leading)
      .padding(.horizontal, ReadingLayout.readingMargin)
      .frame(maxWidth: .infinity)
  }
}
