import SwiftUI

extension Font {
  /// 界面文字一律用它，不直接写 `.headline`、`.footnote`。
  ///
  /// iOS / iPadOS：就是系统文本样式，跟随 Dynamic Type。
  /// macOS：系统样式是给密集的控件面板定的（正文 13pt、脚注 10pt），读文章、管内容的 App 显得太小；
  /// macOS 也不认 `.dynamicTypeSize`（2026-10 实测，设了字号不变），所以给每个样式一个固定字号——
  /// 大致是 macOS 默认值 + 2pt，比 iOS 小一档（Mac 的阅读距离更远，但屏幕像素密度也不同）
  static func app(_ style: TextStyle, design: Design? = nil) -> Font {
    #if os(macOS)
      let (size, weight): (CGFloat, Weight) =
        switch style {
        case .largeTitle: (30, .regular)
        case .title: (24, .regular)
        case .title2: (20, .regular)
        case .title3: (18, .regular)
        case .headline: (15, .semibold)
        case .body: (15, .regular)
        case .callout: (14, .regular)
        case .subheadline: (13, .regular)
        case .footnote: (12, .regular)
        case .caption: (11, .regular)
        case .caption2: (10, .regular)
        case .extraLargeTitle, .extraLargeTitle2: (34, .bold)
        @unknown default: (15, .regular)
        }
      return .system(size: size, weight: weight, design: design)
    #else
      return .system(style, design: design)
    #endif
  }
}

extension View {
  /// List / Form 里没有指定文本样式的行加上它。macOS 上这些行（AppKit 的表格单元）不继承外面设的字体——
  /// 设在 App 根部、List、Section 上都无效（2026-10 实测，行里的文字照样是 13pt），只认行自己身上的。
  /// iOS 上不做任何事：系统样式本来就跟随 Dynamic Type
  @ViewBuilder func rowFont() -> some View {
    #if os(macOS)
      font(.app(.body))
    #else
      self
    #endif
  }

  /// 同上，用于 Section 的页脚说明文字
  @ViewBuilder func footerFont() -> some View {
    #if os(macOS)
      font(.app(.footnote))
    #else
      self
    #endif
  }
}

#if os(macOS)
  /// macOS 上 LabeledContent（左边名称、右边值）的系统样式给两边都设了 13pt 的字体，行上的 rowFont 管不到它们。
  /// 自己排：名称、值都用放大后的正文字号，值是次要颜色、靠右。在 App 根部设置一次
  struct AppLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        configuration.label
          .font(.app(.body))
        Spacer(minLength: 0)
        configuration.content
          .font(.app(.body))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.trailing)
      }
    }
  }
#endif

/// 阅读排版。界面部分一律用 `Font.app`；文章正文另有规则：
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
