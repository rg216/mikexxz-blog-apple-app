import BlogKit
import SwiftUI

extension EnvironmentValues {
  /// 文章滚动区域的高度：竖图最高占它的 80%（网站上的 80svh）
  @Entry var articleViewportHeight: CGFloat = 800
}

/// 单独成段的图片。宽度规则和网站一样：不放大、不超过 #片段指定的显示尺寸和栏宽、竖图不超过视口高度的 80%
struct FigureView: View {
  let image: ImageReference

  @Environment(\.markdownImages) private var images
  @Environment(\.articleViewportHeight) private var viewportHeight

  private var meta: ImageMeta? { image.key.flatMap { images[$0] } }

  var body: some View {
    VStack(spacing: 8) {
      picture
        .accessibilityLabel(image.alt)
        .accessibilityHidden(image.alt.isEmpty)
      if let caption = image.title, !caption.isEmpty {
        Text(caption)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, ReadingLayout.readingMargin)
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private var picture: some View {
    if let meta {
      let ratio = CGFloat(meta.width) / CGFloat(meta.height)
      // 宽度上限同时满足：显示尺寸、原图宽度（不放大）、竖图的高度上限换算出的宽度
      let maxWidth = min(image.maxDisplayWidth, CGFloat(meta.width), viewportHeight * 0.8 * ratio)
      RemoteImage(url: image.url, meta: meta)
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: maxWidth)
    } else {
      // 不是媒体库的图片（或还没补全宽高）：不知道比例，加载完按图片自己的比例显示
      AsyncImage(url: image.url) { phase in
        if let picture = phase.image {
          picture.resizable().scaledToFit()
        } else {
          Rectangle().fill(.quaternary).aspectRatio(4 / 3, contentMode: .fit)
        }
      }
      .frame(maxWidth: image.maxDisplayWidth, maxHeight: viewportHeight * 0.8)
    }
  }
}
