import Foundation

/// 高亮区间：text 的 UTF-16 下标 [start, end)。API 给区间而不是 HTML，客户端自己决定怎么标出来
public struct HighlightRange: Codable, Hashable, Sendable {
  public let start: Int
  public let end: Int
}

public struct HighlightedText: Codable, Hashable, Sendable {
  public let text: String
  public let highlights: [HighlightRange]

  public init(text: String, highlights: [HighlightRange]) {
    self.text = text
    self.highlights = highlights
  }

  /// 把高亮区间转换成 AttributedString 里的范围。
  /// 下标是 UTF-16 的（JS 字符串的单位），Swift 的 String 按字素索引，必须经 utf16 视图换算；
  /// 越界或切开代理对 / 字素的区间丢弃，不让一个坏区间影响整段文字的显示。
  public func attributed(highlight: AttributeContainer) -> AttributedString {
    var result = AttributedString(text)
    let utf16 = text.utf16
    for range in highlights {
      guard range.start >= 0, range.end > range.start, range.end <= utf16.count else { continue }
      let lower = utf16.index(utf16.startIndex, offsetBy: range.start)
      let upper = utf16.index(utf16.startIndex, offsetBy: range.end)
      guard
        let start = lower.samePosition(in: text),
        let end = upper.samePosition(in: text),
        let attributedRange = Range(start..<end, in: result)
      else { continue }
      result[attributedRange].mergeAttributes(highlight)
    }
    return result
  }
}

public struct SearchHit: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let locale: ContentLocale
  public let title: HighlightedText
  /// 正文里包含匹配的一段（只命中标题或标签时是开头一段）
  public let snippet: HighlightedText
  public let publishedAt: Date
  public let tags: [Tag]

  public var id: String { slug }
}

struct SearchResult: Codable, Sendable {
  let items: [SearchHit]
}

public enum SearchLimits {
  /// 与网站的 SEARCH_QUERY_MAX_LENGTH 一致
  public static let queryMaxLength = 100
}
