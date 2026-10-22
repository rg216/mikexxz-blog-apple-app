import Foundation

/*
 * 生成头图（网站 packages/shared 的 cover.ts、cover-options.ts）：两步，都由作者手动触发。
 *   1. 画面描述：Claude 读标题、标签、正文，写一段给图像模型的英文描述和一句图片描述（POST /admin/covers/brief）
 *   2. 出图：OpenAI GPT Image 按"头图风格 + 画面描述"出一张 16:9 的图（POST /admin/covers/generate，NDJSON 流）
 * 选中的那张由 App 走和手动上传同一条路进媒体库（ImagePreparation → 预签名直传 → 确认），再设为头图；没选的不进存储。
 */

/// GET /admin/covers/config：两步各自能不能用、用哪个模型
public struct CoverConfig: Decodable, Hashable, Sendable {
  public struct Step: Decodable, Hashable, Sendable {
    public let available: Bool
    public let model: String
    /// 只有出图有（low / medium / high）
    public let quality: String?
    /// 不能用时的原因：not_configured / rate_limiter_unavailable（和翻译的 TranslationConfig 相同）
    public let reason: String?
  }

  public let brief: Step
  public let image: Step
}

/// POST /admin/covers/brief：表单里此刻的内容（新文章还没保存也能用）
public struct CoverBriefInput: Encodable, Sendable {
  public let title: String
  /// 标签的名称（不是 slug）
  public let tags: [String]
  public let contentMd: String
  /// 作者给的方向（"用钥匙比喻缓存"），可选；nil 时不发这个键
  public let direction: String?

  public init(title: String, tags: [String], contentMd: String, direction: String?) {
    self.title = title
    self.tags = tags
    self.contentMd = contentMd
    let trimmed = direction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.direction = trimmed.isEmpty ? nil : trimmed
  }
}

public struct CoverBriefResult: Decodable, Hashable, Sendable {
  /// 画面描述（英文），给作者看、可改，第二步原样发回
  public let prompt: String
  /// 图片描述（原文语言），上传后写进媒体库，用作头图的 alt
  public let alt: String
  public let model: String
  public let usage: TranslationUsage
}

public struct CoverImageUsage: Codable, Hashable, Sendable {
  public let inputTokens: Int
  public let outputTokens: Int
}

/// 生成好的一张图
public struct CoverImage: Hashable, Sendable {
  /// image/webp、image/png 或 image/jpeg
  public let contentType: String
  public let data: Data
  public let model: String
  public let quality: String
  public let usage: CoverImageUsage

  public init(contentType: String, data: Data, model: String, quality: String, usage: CoverImageUsage) {
    self.contentType = contentType
    self.data = data
    self.model = model
    self.quality = quality
    self.usage = usage
  }
}

/// 出图的 NDJSON 流里的一行：若干 ping / partial，最后是 done 或 error
public enum CoverImageStreamEvent: Decodable, Hashable, Sendable {
  /// 心跳：还在生成，没有新的预览
  case ping
  /// 生成过程中的预览图：只用来尽早看出方向不对、及时停止，不能当结果用
  case partial(index: Int, contentType: String, data: Data)
  case done(CoverImage)
  case error(code: String, message: String)
  /// 不认识的事件类型（服务器更新了）：忽略
  case unknown

  private enum CodingKeys: String, CodingKey {
    case type, index, contentType, image, model, quality, usage, code, message
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func image() throws -> Data {
      // 服务器发的是标准 base64（不换行），解码失败就是数据坏了
      guard let data = Data(base64Encoded: try container.decode(String.self, forKey: .image)) else {
        throw DecodingError.dataCorruptedError(forKey: .image, in: container, debugDescription: "不是 base64")
      }
      return data
    }
    switch try container.decode(String.self, forKey: .type) {
    case "ping": self = .ping
    case "partial":
      self = .partial(index: try container.decode(Int.self, forKey: .index), contentType: try container.decode(String.self, forKey: .contentType), data: try image())
    case "done":
      self = .done(
        CoverImage(
          contentType: try container.decode(String.self, forKey: .contentType), data: try image(), model: try container.decode(String.self, forKey: .model),
          quality: try container.decode(String.self, forKey: .quality), usage: try container.decode(CoverImageUsage.self, forKey: .usage)))
    case "error": self = .error(code: try container.decode(String.self, forKey: .code), message: try container.decode(String.self, forKey: .message))
    default: self = .unknown
    }
  }
}

/// 可选项和上限（网站的 cover-options.ts、cover.ts；2026-10 核对）
public enum CoverOptions {
  public struct Option: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
  }

  public static let imageModels: [Option] = [
    .init(id: "gpt-image-2.5-flare", name: "GPT Image 2.5 Flare", summary: "OpenAI 定位为快速、高质量的日常出图，默认选择"),
    .init(id: "gpt-image-2.5-sunburst", name: "GPT Image 2.5 Sunburst", summary: "OpenAI 定位为编辑精度最高；这里只生成新图，多半用不到"),
  ]

  public static let qualities: [Option] = [
    .init(id: "low", name: "低", summary: "最便宜、最快，适合先试方向"),
    .init(id: "medium", name: "中", summary: "默认。头图在列表里只显示成缩略图，通常够用"),
    .init(id: "high", name: "高", summary: "细节更多，token 约是“中”的 4 倍，耗时也更长"),
  ]

  /// 不认识的（网站加了新模型、新画质）显示 ID 本身
  public static func imageModelName(_ id: String) -> String { imageModels.first { $0.id == id }?.name ?? id }
  public static func qualityName(_ id: String) -> String { qualities.first { $0.id == id }?.name ?? id }

  public static let promptMaxLength = 4000
  public static let directionMaxLength = 500
  /// 和媒体库的图片描述同一个上限
  public static let altMaxLength = 500
  public static let styleMaxLength = 4000

  /// 默认的头图风格（网站的 DEFAULT_COVER_STYLE，"恢复默认"用）。服务器没改过时返回的也是它
  public static let defaultStyle = [
    "Cover image for a personal technical blog post, 16:9, as eye-catching as a great YouTube thumbnail.",
    "- One bold focal subject that reads instantly, even as a tiny thumbnail. Large in the frame, simple strong silhouette.",
    "- Keep everything important inside the central three quarters of the width: the image is also cropped to 4:3 for list cards.",
    "- High contrast, saturated but harmonious colors, dramatic lighting, a clean uncluttered background with some depth.",
    "- Graphic rather than photographic: polished 3D render or bold flat illustration. No stock-photo look.",
    "- Text: none by default. Only if it clearly helps, at most one to three short words in huge, bold, sans-serif letters,",
    "  and only language-neutral words such as product names, code keywords or numbers (for example Next.js, v5, 404).",
    "  Never Chinese or Japanese characters, never sentences, captions, small print, watermarks, or real company logos.",
  ].joined(separator: "\n")

  /// 媒体库里的文件名：cover-<slug>-<第几张>.webp（网站的 coverFileName）。slug 还没填时用 untitled
  public static func fileName(slug: String, n: Int, contentType: String) -> String {
    var base = ""
    var pendingDash = false
    for scalar in slug.trimmingCharacters(in: .whitespaces).lowercased().unicodeScalars {
      if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-" {
        if pendingDash && !base.isEmpty { base.append("-") }
        pendingDash = false
        base.unicodeScalars.append(scalar)
      } else {
        pendingDash = true
      }
    }
    base = String(base.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
    let ext =
      switch contentType {
      case "image/webp": "webp"
      case "image/png": "png"
      case "image/jpeg": "jpg"
      default: "img"
      }
    return "cover-\(base.isEmpty ? "untitled" : base)-\(n).\(ext)"
  }
}
