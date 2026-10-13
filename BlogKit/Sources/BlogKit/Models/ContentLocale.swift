import Foundation

/// 文章内容的语言（站点的 `locales`：zh / en / ja，BCP 47 标签）。
///
/// 不用 enum：App 装在读者手机上，可能几个月不更新，而网站随时可能加一种语言。
/// enum 遇到不认识的值会让整个响应解码失败（列表里一个标签的 locale 是 "ko" 就什么都显示不出来）；
/// 包一层字符串则照常解码，只是 `supported` 里没有它、菜单里不出现。
public struct ContentLocale: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var id: String { rawValue }

  public static let zh = ContentLocale(rawValue: "zh")
  public static let en = ContentLocale(rawValue: "en")
  public static let ja = ContentLocale(rawValue: "ja")

  /// 与网站 `@blog/shared` 的 `locales` 同序
  public static let supported: [ContentLocale] = [.zh, .en, .ja]

  /// API 的默认语言，也是网址不带前缀的语言
  public static let `default` = ContentLocale.zh

  /// 完整的语言标签：中文用 zh-CN，排版时据此选简体字形（中日共用汉字，见网站的 localeInfo）
  public var languageTag: String {
    switch self {
    case .zh: "zh-CN"
    default: rawValue
    }
  }

  public var language: Locale.Language { Locale.Language(identifier: languageTag) }

  /// 语言自称：切换菜单里无论界面是什么语言，都用该语言自己的写法
  public var endonym: String {
    switch self {
    case .zh: "中文"
    case .en: "English"
    case .ja: "日本語"
    default: Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
    }
  }

  /// 从首选语言列表里挑第一个站点支持的语言；都不支持时用默认语言。
  /// 繁体中文的读者也归到 zh：站上只有简体，但对他们来说比英文好读。
  public static func preferred(from identifiers: [String]) -> ContentLocale {
    for identifier in identifiers {
      guard let code = Locale.Language(identifier: identifier).languageCode?.identifier else { continue }
      if let match = supported.first(where: { $0.rawValue == code }) { return match }
    }
    return .default
  }
}
