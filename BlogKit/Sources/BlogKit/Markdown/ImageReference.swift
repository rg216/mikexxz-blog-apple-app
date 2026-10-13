import CoreGraphics
import Foundation

/// 正文里的一张图片，按网站 `@blog/shared` 的 media.ts 约定解读：
/// - 地址里的 key（images/2026/10/<16 位随机串>.jpg）识别媒体库图片，宽高和尺寸版本按 key 查 `PublicPost.images`
/// - 尺寸版本与原图同名、加宽度后缀：<随机串>-640w.jpg
/// - 显示尺寸写在 #片段里：#small / #medium / #large（默认）/ #w=320
public struct ImageReference: Hashable, Sendable {
  /// 去掉 #片段之后的地址
  public let url: URL
  public let alt: String
  /// Markdown 的 title，单独成段的图片用作图注
  public let title: String?
  public let size: ImageDisplaySize?

  public init(url: URL, alt: String, title: String?, size: ImageDisplaySize?) {
    self.url = url
    self.alt = alt
    self.title = title
    self.size = size
  }

  /// 解析 Markdown 里写的地址；不是合法网址时为 nil
  public init?(source: String, alt: String, title: String?) {
    let (bare, size) = Self.parseSize(source)
    guard let url = URL(string: bare) else { return nil }
    self.init(url: url, alt: alt, title: title, size: size)
  }

  /// 媒体库原图的 key；不是媒体库的图片为 nil
  public var key: String? { Self.key(of: url.absoluteString) }

  /// 显示宽度上限（pt）：没写尺寸的单独成段图片默认"大"，即出血栏宽
  public var maxDisplayWidth: CGFloat {
    switch size {
    case .preset(let preset): preset.width
    case .width(let width): CGFloat(width)
    case nil: ImageSizePreset.large.width
    }
  }

  // MARK: - 规则（与网站同一套）

  static func parseSize(_ source: String) -> (String, ImageDisplaySize?) {
    guard let hash = source.firstIndex(of: "#") else { return (source, nil) }
    let bare = String(source[..<hash])
    let fragment = source[source.index(after: hash)...]
    if let preset = ImageSizePreset(rawValue: String(fragment)) { return (bare, .preset(preset)) }
    if let match = fragment.wholeMatch(of: /w=(\d{1,4})/), let width = Int(match.1), customWidthRange.contains(width) {
      return (bare, .width(width))
    }
    // 不认识的片段原样保留（可能是普通的锚点）
    return (source, nil)
  }

  public static let customWidthRange = 40...2000

  static func key(of url: String) -> String? {
    guard let match = url.firstMatch(of: /images\/\d{4}\/\d{2}\/[\w-]{16}(?:-\d+w)?\.(?:jpg|png|webp|avif|gif)/) else { return nil }
    return originalKey(String(match.output))
  }

  /// 引用小图也算引用了原图。只认 16 位随机串之后的后缀——随机串本身也可能恰好以 "-640w" 结尾
  private static func originalKey(_ key: String) -> String {
    guard let match = key.wholeMatch(of: /(images\/\d{4}\/\d{2}\/[\w-]{16})-\d+w(\.\w+)/) else { return key }
    return String(match.1) + String(match.2)
  }

  /// 原图地址 → 某个宽度版本的地址
  public static func variantURL(_ url: URL, width: Int) -> URL {
    let ext = url.pathExtension
    guard !ext.isEmpty else { return url }
    var result = url.deletingPathExtension()
    let name = result.lastPathComponent + "-\(width)w"
    result.deleteLastPathComponent()
    return result.appending(component: name).appendingPathExtension(ext)
  }

  /// 按实际要显示的像素宽度挑最合适的文件：比它宽的最窄版本；版本都不够宽就用原图。
  /// 版本只生成比原图窄的，所以原图总是最宽的那个
  public static func bestSource(_ url: URL, meta: ImageMeta?, pixelWidth: CGFloat) -> URL {
    guard let meta else { return url }
    let candidate = meta.variants.sorted().first { CGFloat($0) >= pixelWidth && $0 < meta.width }
    return candidate.map { variantURL(url, width: $0) } ?? url
  }
}

public enum ImageSizePreset: String, Hashable, Sendable {
  case small, medium, large

  /// 与网站的 IMAGE_DISPLAY_WIDTHS 一致：半栏 / 正文栏 / 出血栏
  public var width: CGFloat {
    switch self {
    case .small: 340
    case .medium: 680
    case .large: 864
    }
  }
}

public enum ImageDisplaySize: Hashable, Sendable {
  case preset(ImageSizePreset)
  case width(Int)
}
