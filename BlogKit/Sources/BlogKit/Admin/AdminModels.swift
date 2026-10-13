import Foundation

// 后台接口的模型，与网站 packages/shared 的 zod schema 一一对应。

// MARK: - 登录

public struct SessionInfo: Codable, Hashable, Sendable {
  public struct User: Codable, Hashable, Sendable {
    public let displayName: String
  }

  public let user: User
  /// session 的绝对过期时间（闲置 7 天也会失效）
  public let expiresAt: Date
}

/// 用授权码换来的 token（就是一个 session，放在 Authorization: Bearer 里）
public struct AppToken: Codable, Sendable {
  public let token: String
  public let user: SessionInfo.User
  public let expiresAt: Date

  public var session: SessionInfo { SessionInfo(user: user, expiresAt: expiresAt) }
}

public struct Passkey: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
  /// multiDevice：可同步（iCloud 钥匙串）；singleDevice：绑定单台设备（硬件密钥）
  public let deviceType: String
  public let backedUp: Bool
  public let createdAt: Date
  public let lastUsedAt: Date?
}

// MARK: - 文章

public enum PostStatus: String, Codable, Hashable, Sendable, CaseIterable {
  case draft, published
}

public struct AdminTranslationSummary: Codable, Hashable, Sendable, Identifiable {
  public let locale: ContentLocale
  public let title: String
  public let origin: TranslationOrigin
  /// 生成译文的模型（机器翻译）；人工译文为 nil
  public let model: String?
  public let translatedAt: Date
  public let sourceHash: String
  /// 原文在译文之后改过
  public let outdated: Bool

  public var id: ContentLocale { locale }
}

public struct AdminTranslation: Codable, Hashable, Sendable {
  public let locale: ContentLocale
  public let title: String
  public let contentMd: String
  public let excerpt: String
  public let origin: TranslationOrigin
  public let model: String?
  public let translatedAt: Date
  public let sourceHash: String
  public let outdated: Bool
}

public struct AdminPost: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let slug: String
  public let title: String
  public let contentMd: String
  public let excerpt: String
  public let status: PostStatus
  public let publishedAt: Date?
  public let tags: [Tag]
  public let cover: PostCover?
  public let images: [String: ImageMeta]
  public let locale: ContentLocale
  public let createdAt: Date
  public let updatedAt: Date
  public let sourceLocale: ContentLocale
  /// 当前原文的指纹，保存译文时原样传回
  public let sourceHash: String
  public let translations: [AdminTranslationSummary]
}

/// 新建 / 修改文章。修改时只编码给出的字段（PATCH 是部分更新，没给的字段保持不变）
public struct PostInput: Encodable, Sendable {
  public var slug: String?
  public var title: String?
  public var contentMd: String?
  public var status: PostStatus?
  /// 标签 slug，按显示顺序；只能引用已有的标签
  public var tags: [String]?
  /// 头图（媒体库图片的地址）；.some(nil) 表示去掉头图
  public var coverImage: URL??

  public init(slug: String? = nil, title: String? = nil, contentMd: String? = nil, status: PostStatus? = nil, tags: [String]? = nil, coverImage: URL?? = nil) {
    self.slug = slug
    self.title = title
    self.contentMd = contentMd
    self.status = status
    self.tags = tags
    self.coverImage = coverImage
  }

  private enum CodingKeys: String, CodingKey {
    case slug, title, contentMd, status, tags, coverImage
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(slug, forKey: .slug)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(contentMd, forKey: .contentMd)
    try container.encodeIfPresent(status, forKey: .status)
    try container.encodeIfPresent(tags, forKey: .tags)
    // 双层可选：外层 nil 是"不改"，内层 nil 是"改成没有头图"（JSON null）
    if let coverImage {
      if let url = coverImage { try container.encode(url, forKey: .coverImage) } else { try container.encodeNil(forKey: .coverImage) }
    }
  }
}

/// 保存译文（PUT，整体替换）。generated：未经修改的机器译文，服务端会再做一次结构校验
public struct TranslationInput: Encodable, Sendable {
  public struct Generated: Encodable, Sendable {
    public let model: String
  }

  public let title: String
  public let contentMd: String
  public let sourceHash: String
  public let generated: Generated?

  public init(title: String, contentMd: String, sourceHash: String, generatedModel: String?) {
    self.title = title
    self.contentMd = contentMd
    self.sourceHash = sourceHash
    generated = generatedModel.map(Generated.init(model:))
  }
}

// MARK: - 大模型翻译

public struct TranslationConfig: Codable, Hashable, Sendable {
  public let available: Bool
  public let model: String
  public let tagModel: String
  /// not_configured / rate_limiter_unavailable
  public let reason: String?
}

/// 正文按服务器的切分规则分成几段（App 不自己切，见网站的 translationPlanSchema）
public struct TranslationPlan: Codable, Hashable, Sendable {
  public let sourceHash: String
  public let segments: Int
}

public struct TranslationUsage: Codable, Hashable, Sendable {
  public let inputTokens: Int
  public let outputTokens: Int
  public let cacheReadInputTokens: Int
  public let cacheCreationInputTokens: Int

  public static let zero = TranslationUsage(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)

  public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cacheReadInputTokens = cacheReadInputTokens
    self.cacheCreationInputTokens = cacheCreationInputTokens
  }

  public static func + (lhs: TranslationUsage, rhs: TranslationUsage) -> TranslationUsage {
    TranslationUsage(
      inputTokens: lhs.inputTokens + rhs.inputTokens,
      outputTokens: lhs.outputTokens + rhs.outputTokens,
      cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens,
      cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens)
  }
}

public struct TranslationTitleResult: Codable, Hashable, Sendable {
  public let title: String
  public let model: String
  public let usage: TranslationUsage
}

/// 正文一段的 NDJSON 流里的一行
public enum TranslationStreamEvent: Decodable, Hashable, Sendable {
  /// 心跳：模型还在思考，没有输出
  case ping
  case delta(String)
  case done(text: String, stopReason: String, model: String, usage: TranslationUsage)
  case error(code: String, message: String)
  /// 不认识的事件类型（服务器更新了）：忽略
  case unknown

  private enum CodingKeys: String, CodingKey {
    case type, text, stopReason, model, usage, code, message
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .type) {
    case "ping": self = .ping
    case "delta": self = .delta(try container.decode(String.self, forKey: .text))
    case "done":
      self = .done(
        text: try container.decode(String.self, forKey: .text),
        stopReason: try container.decode(String.self, forKey: .stopReason),
        model: try container.decode(String.self, forKey: .model),
        usage: try container.decode(TranslationUsage.self, forKey: .usage))
    case "error": self = .error(code: try container.decode(String.self, forKey: .code), message: try container.decode(String.self, forKey: .message))
    default: self = .unknown
    }
  }
}

public enum ModelNames {
  /// 与网站的 TRANSLATION_MODEL_MAX_LENGTH 一致
  public static let maxLength = 100

  /// 网站 combineModelNames 的移植：各次请求实际服务的模型去重后用 ", " 连接，超长时保留放得下的几个再加 ", …"
  public static func combine(_ models: [String]) -> String {
    var seen = Set<String>()
    let unique = models.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    let joined = unique.joined(separator: ", ")
    if joined.utf16.count <= maxLength { return joined }
    guard let first = unique.first else { return "" }
    if unique.count == 1 { return fit(first) }
    let more = ", …"
    var kept: [String] = []
    for model in unique {
      if ((kept + [model]).joined(separator: ", ") + more).utf16.count > maxLength { break }
      kept.append(model)
    }
    if !kept.isEmpty { return kept.joined(separator: ", ") + more }
    return prefix(first, maxLength - more.utf16.count - 1) + "…" + more
  }

  /// fitModelName：超长时截断并以 "…" 结尾
  public static func fit(_ model: String) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespaces)
    return trimmed.utf16.count > maxLength ? prefix(trimmed, maxLength - 1) + "…" : trimmed
  }

  /// 按 UTF-16 长度截取（网站按 JS 字符串长度计），不切开代理对
  private static func prefix(_ string: String, _ length: Int) -> String {
    var result = ""
    var count = 0
    for character in string {
      let size = character.utf16.count
      if count + size > length { break }
      result.append(character)
      count += size
    }
    return result
  }
}

// MARK: - 标签

public struct AdminTag: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let slug: String
  /// 原文语言（中文）的名称
  public let name: String
  /// 其他语言的译名；缺的语言前台显示原文名称
  public let translations: [String: String]
  /// 用到它的文章数（含草稿）
  public let postCount: Int
  public let publishedCount: Int

  /// 需要译名的语言：除原文语言（中文）外的全部（网站的 tagTranslationLocales）
  public static let translationLocales = ContentLocale.supported.filter { $0 != .default }

  public var missingTranslations: [ContentLocale] {
    Self.translationLocales.filter { (translations[$0.rawValue] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
  }
}

public struct TagInput: Encodable, Sendable {
  public var slug: String?
  public var name: String?
  /// 给了就必须是全部需要译名的语言
  public var translations: [String: String]?

  public init(slug: String? = nil, name: String? = nil, translations: [String: String]? = nil) {
    self.slug = slug
    self.name = name
    self.translations = translations
  }
}

public struct TagTranslateResult: Codable, Hashable, Sendable {
  public let translations: [String: String]
  public let model: String
  public let usage: TranslationUsage
}

// MARK: - 评论

public enum CommentStatus: String, Codable, Hashable, Sendable, CaseIterable {
  case pending, approved, rejected
}

public enum CommenterTrust: String, Codable, Hashable, Sendable, CaseIterable {
  case `default`, trusted, blocked
}

public struct AdminCommenter: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let githubId: Int
  public let login: String
  public let name: String?
  public let avatarUrl: URL
  public let trust: CommenterTrust
  public let createdAt: Date
}

public struct AdminComment: Codable, Hashable, Sendable, Identifiable {
  public struct PostRef: Codable, Hashable, Sendable {
    public let slug: String
    public let title: String
  }

  public struct ParentRef: Codable, Hashable, Sendable {
    public let id: Int
    public let login: String
    public let excerpt: String
  }

  public let id: Int
  public let post: PostRef
  public let author: AdminCommenter
  public let bodyMd: String
  public let status: CommentStatus
  public let createdAt: Date
  public let parent: ParentRef?
}

// MARK: - 媒体库

public struct AdminImage: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let url: URL
  public let contentType: String
  public let size: Int
  public let filename: String
  public let width: Int?
  public let height: Int?
  public let variants: [Int]
  public let folderId: Int?
  public let description: String
  /// 引用它的文章数
  public let usage: Int
  public let createdAt: Date

  public var meta: ImageMeta? {
    guard let width, let height else { return nil }
    return ImageMeta(width: width, height: height, variants: variants)
  }
}

public struct AdminImageDetail: Codable, Hashable, Sendable {
  public struct PostRef: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let slug: String
    public let title: String
    public let status: PostStatus
  }

  public let image: AdminImage
  public let posts: [PostRef]

  public init(from decoder: any Decoder) throws {
    image = try AdminImage(from: decoder)
    posts = try decoder.container(keyedBy: CodingKeys.self).decode([PostRef].self, forKey: .posts)
  }

  public func encode(to encoder: any Encoder) throws {
    try image.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(posts, forKey: .posts)
  }

  private enum CodingKeys: String, CodingKey {
    case posts
  }
}

public struct MediaFolder: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let name: String
  public let imageCount: Int
}

public struct ImageUploadRequest: Encodable, Sendable {
  public struct Variant: Encodable, Sendable {
    public let width: Int
    public let size: Int

    public init(width: Int, size: Int) {
      self.width = width
      self.size = size
    }
  }

  public let contentType: String
  public let size: Int
  public let filename: String
  public let variants: [Variant]
  public let folderId: Int?

  public init(contentType: String, size: Int, filename: String, variants: [Variant], folderId: Int?) {
    self.contentType = contentType
    self.size = size
    self.filename = filename
    self.variants = variants
    self.folderId = folderId
  }

  private enum CodingKeys: String, CodingKey {
    case contentType, size, filename, variants, folderId
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(contentType, forKey: .contentType)
    try container.encode(size, forKey: .size)
    try container.encode(filename, forKey: .filename)
    try container.encode(variants, forKey: .variants)
    if let folderId { try container.encode(folderId, forKey: .folderId) } else { try container.encodeNil(forKey: .folderId) }
  }
}

/// 预签名的上传地址：原样带上 headers（它们参与了签名）PUT 文件
public struct PresignedPut: Codable, Hashable, Sendable {
  public let url: URL
  public let method: String
  public let headers: [String: String]
  public let width: Int?
}

public struct ImageUpload: Codable, Hashable, Sendable {
  public let image: AdminImage
  public let upload: PresignedPut
  public let variants: [PresignedPut]
  public let expiresAt: Date
}

public struct ImageUpdateInput: Encodable, Sendable {
  public var filename: String?
  public var description: String?

  public init(filename: String? = nil, description: String? = nil) {
    self.filename = filename
    self.description = description
  }
}

// MARK: - 设置与状态

public struct SiteSettings: Codable, Hashable, Sendable {
  public var translationModel: String
  public var tagTranslationModel: String
}

/// 可选的翻译模型（网站的 translationModels；2026-10 按官方文档核对）
public struct TranslationModelInfo: Hashable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let summary: String
  /// 每百万 token 的价格（美元）
  public let inputPrice: Double
  public let outputPrice: Double

  public static let all: [TranslationModelInfo] = [
    .init(id: "claude-haiku-5-5", name: "Haiku 5.5", summary: "最快、最便宜。适合标签名这类短文本；长文的准确度不如 Sonnet", inputPrice: 0.1, outputPrice: 0.5),
    .init(id: "claude-sonnet-5-5", name: "Sonnet 5.5", summary: "速度和质量的平衡，默认选择", inputPrice: 2, outputPrice: 10),
    .init(id: "claude-opus-5-5", name: "Opus 5.5", summary: "更强的理解和表达，价格是 Sonnet 的 2 倍", inputPrice: 4, outputPrice: 20),
    .init(id: "claude-fable-5-1", name: "Fable 5.1", summary: "最强的推理，最慢，价格是 Opus 的 2.5 倍；翻译一般用不到", inputPrice: 10, outputPrice: 50),
  ]

  /// 模型 ID 的显示名；不认识的（网站加了新模型）显示 ID 本身
  public static func name(of id: String) -> String {
    all.first { $0.id == id }?.name ?? id
  }
}

public enum StatusState: String, Codable, Hashable, Sendable {
  case ok, warning, error, off

  /// 一组状态里最严重的（error > warning > ok > off）
  public static func worst(_ states: [StatusState]) -> StatusState {
    [.error, .warning, .ok, .off].first { states.contains($0) } ?? .off
  }
}

public struct StatusCheck: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let state: StatusState
  /// 中文的一句话说明（后台固定中文）
  public let summary: String
  public let latencyMs: Double?
}

public struct JobStatus: Codable, Hashable, Sendable, Identifiable {
  public let name: String
  public let state: StatusState
  public let lastRunAt: Date?
  public let lastSuccessAt: Date?
  public let detail: String?

  public var id: String { name }
}

public struct SystemStatus: Codable, Hashable, Sendable {
  public let version: String?
  public let checkedAt: Date
  public let checks: [StatusCheck]
  public let jobs: [JobStatus]
}
