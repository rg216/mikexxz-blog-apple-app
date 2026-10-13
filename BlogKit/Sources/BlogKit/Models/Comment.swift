import Foundation

/// 评论者的公开资料（来自 GitHub）
public struct CommentAuthor: Codable, Hashable, Sendable {
  public let login: String
  public let name: String?
  public let avatarUrl: URL

  public var displayName: String { name ?? login }
}

public struct CommentReplyTarget: Codable, Hashable, Sendable {
  public let login: String
}

public struct PublicComment: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  /// 作者自己删除了的楼主占位为 nil
  public let author: CommentAuthor?
  /// Markdown；已删除的为空串
  public let bodyMd: String
  public let createdAt: Date
  public let editedAt: Date?
  public let deleted: Bool
  /// 回复的是楼中楼里的另一条回复时，标出被回复的人
  public let replyTo: CommentReplyTarget?
}

/// 楼中楼两层：顶层评论 + 它下面按时间排列的所有回复。
/// JSON 里回复和楼主的字段平铺在同一个对象上（`publicCommentSchema.extend({ replies })`）
public struct CommentThread: Codable, Hashable, Sendable, Identifiable {
  public let comment: PublicComment
  public let replies: [PublicComment]

  public var id: Int { comment.id }

  private enum CodingKeys: String, CodingKey {
    case replies
  }

  public init(from decoder: any Decoder) throws {
    comment = try PublicComment(from: decoder)
    replies = try decoder.container(keyedBy: CodingKeys.self).decode([PublicComment].self, forKey: .replies)
  }

  public func encode(to encoder: any Encoder) throws {
    try comment.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(replies, forKey: .replies)
  }
}

public struct CommentList: Codable, Hashable, Sendable {
  public let threads: [CommentThread]
  /// 已显示的评论总数
  public let count: Int
}
