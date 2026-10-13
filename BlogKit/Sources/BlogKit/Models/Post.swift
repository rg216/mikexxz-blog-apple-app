import Foundation

// 与网站 packages/shared 的 zod schema 一一对应（字段名相同，camelCase）。
// Codable 默认忽略不认识的字段：API 加字段不会让旧版 App 出错；删字段或改类型才会。

public struct Tag: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let name: String
  /// name 是哪种语言：没有译名的标签退回原文名称，显示时据此设置排版语言
  public let locale: ContentLocale

  public var id: String { slug }

  public init(slug: String, name: String, locale: ContentLocale) {
    self.slug = slug
    self.name = name
    self.locale = locale
  }
}

public struct TagWithCount: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let name: String
  public let locale: ContentLocale
  /// 该语言下带这个标签的已发布文章数
  public let count: Int

  public var id: String { slug }
  public var tag: Tag { Tag(slug: slug, name: name, locale: locale) }
}

/// 媒体库图片的尺寸信息：宽高来自 API 从文件头解析的结果，variants 是生成过的窄版本宽度
public struct ImageMeta: Codable, Hashable, Sendable {
  public let width: Int
  public let height: Int
  public let variants: [Int]

  public init(width: Int, height: Int, variants: [Int]) {
    self.width = width
    self.height = height
    self.variants = variants
  }
}

/// 头图：宽高未知（旧图片还没补全）时为 nil
public struct PostCover: Codable, Hashable, Sendable {
  public let url: URL
  public let alt: String
  public let width: Int?
  public let height: Int?
  public let variants: [Int]

  public var meta: ImageMeta? {
    guard let width, let height else { return nil }
    return ImageMeta(width: width, height: height, variants: variants)
  }
}

/// 列表项（不带正文）
public struct PostSummary: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let title: String
  public let excerpt: String
  /// 公开接口只返回已发布的文章，数据库约束保证它有发布时间
  public let publishedAt: Date
  public let tags: [Tag]
  public let cover: PostCover?
  /// title / excerpt 实际的语言
  public let locale: ContentLocale

  public var id: String { slug }
}

public enum TranslationOrigin: String, Codable, Sendable {
  /// 大模型生成、作者过目后原样保存
  case machine
  /// 作者手写或改过
  case human
}

public struct TranslationInfo: Codable, Hashable, Sendable {
  public let origin: TranslationOrigin
  public let translatedAt: Date
  /// 译文生成之后原文又改过
  public let outdated: Bool
}

/// 单篇文章：按请求的语言返回，没有该语言的译文时返回原文（locale 为原文语言）
public struct PublicPost: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let title: String
  public let contentMd: String
  public let excerpt: String
  public let publishedAt: Date
  public let tags: [Tag]
  public let cover: PostCover?
  /// 正文引用的媒体库图片，按原图 key 索引（见 `ImageReference.key`）
  public let images: [String: ImageMeta]
  public let locale: ContentLocale
  public let sourceLocale: ContentLocale
  /// 原文 + 已有译文的语言
  public let availableLocales: [ContentLocale]
  /// 读者看的是原文时为 nil
  public let translation: TranslationInfo?

  public var id: String { slug }
}

public struct ArchiveItem: Codable, Hashable, Sendable, Identifiable {
  public let slug: String
  public let title: String
  public let publishedAt: Date
  public let locale: ContentLocale

  public var id: String { slug }
}

/// 游标分页；nextCursor 为 nil 表示没有下一页。游标不透明，原样传回
public struct Page<Item: Codable & Sendable>: Codable, Sendable {
  public let items: [Item]
  public let nextCursor: String?
}

public struct ViewCount: Codable, Sendable {
  /// 服务端没有配置 Redis 时为 nil（不显示数字）
  public let views: Int?
}

/// 文章筛选条件（列表和搜索接口共用）：文章须同时带有全部标签；月份范围两端都含，按站点时区
public struct PostFilter: Hashable, Sendable {
  public static let maxTags = 10

  public var tags: [String]
  public var from: YearMonth?
  public var to: YearMonth?

  public init(tags: [String] = [], from: YearMonth? = nil, to: YearMonth? = nil) {
    self.tags = tags
    self.from = from
    self.to = to
  }

  public var isEmpty: Bool { tags.isEmpty && from == nil && to == nil }

  var queryItems: [URLQueryItem] {
    var items: [URLQueryItem] = []
    if !tags.isEmpty { items.append(URLQueryItem(name: "tags", value: tags.prefix(Self.maxTags).joined(separator: ","))) }
    if let from { items.append(URLQueryItem(name: "from", value: from.description)) }
    if let to { items.append(URLQueryItem(name: "to", value: to.description)) }
    return items
  }
}
