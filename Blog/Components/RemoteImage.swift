import BlogKit
import SwiftUI

/// 媒体库图片：按实际显示宽度 × 屏幕倍率挑最合适的尺寸版本（网页上 srcset + sizes 的作用）。
/// 大小由外面决定（aspectRatio / frame），这里只负责填满
struct RemoteImage: View {
  let url: URL
  let meta: ImageMeta?
  var contentMode: ContentMode = .fit

  @Environment(\.displayScale) private var displayScale
  /// 只增不减：转屏变窄时不必换成更小的文件重新下载
  @State private var width: CGFloat = 0

  var body: some View {
    Rectangle()
      .fill(.quaternary)
      .overlay {
        if width > 0 {
          AsyncImage(url: ImageReference.bestSource(url, meta: meta, pixelWidth: width * displayScale)) { phase in
            switch phase {
            case .success(let image):
              image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
              Image(systemName: "photo")
                .font(.app(.title2))
                .foregroundStyle(.tertiary)
            default:
              Color.clear
            }
          }
        }
      }
      .clipped()
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(width, $0) }
  }
}
