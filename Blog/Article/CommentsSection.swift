import BlogKit
import SwiftUI

/// 评论（只读）。和网站一样不随页面加载，滚到附近才请求。
///
/// 发评论要 GitHub 登录，网站的登录流程是 OAuth 回跳 + `__Host-` cookie，为浏览器设计；
/// App 里要做得用 ASWebAuthenticationSession 和一种不靠 cookie 的凭证，API 那边也要改，先引导去网页上评论
struct CommentsSection: View {
  let post: PublicPost

  @Environment(\.blogClient) private var client
  @State private var state: Loadable<[RenderedThread]>?
  @State private var isVisible = false
  @State private var hasStarted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Divider()
      Text("Comments")
        .font(.app(.title2).bold())
        .accessibilityAddTraits(.isHeader)
      switch state {
      case nil, .loading:
        ProgressView()
          .frame(maxWidth: .infinity)
      case .failed(let error):
        Text(error.message)
          .foregroundStyle(.secondary)
        Button("Try Again") { Task { await load() } }
      case .loaded(let threads):
        if threads.isEmpty {
          Text("No comments yet.")
            .foregroundStyle(.secondary)
        }
        ForEach(threads) { thread in
          CommentThreadView(thread: thread)
        }
      }
      Link(destination: webCommentsURL) {
        Label("Comment on the Web", systemImage: "safari")
      }
      .font(.app(.subheadline).weight(.semibold))
      .opensLinksInBrowser()
    }
    .environment(\.markdownTheme, .comment)
    .onScrollVisibilityChange(threshold: 0.01) { visible in
      if visible { isVisible = true }
    }
    .task(id: isVisible) {
      guard isVisible, !hasStarted else { return }
      hasStarted = true
      await load()
    }
  }

  private var webCommentsURL: URL {
    var components = URLComponents(url: SiteLinks.postURL(slug: post.slug, locale: post.locale), resolvingAgainstBaseURL: false)!
    components.fragment = "comments"
    return components.url!
  }

  private func load() async {
    state = .loading
    do {
      let list = try await client.comments(slug: post.slug)
      state = .loaded(await RenderedThread.prepare(list.threads))
    } catch .cancelled {
      state = nil
      hasStarted = false
    } catch {
      state = .failed(error)
    }
  }
}

struct RenderedComment: Identifiable {
  let comment: PublicComment
  let blocks: [MarkdownBlock]
  var id: Int { comment.id }
}

struct RenderedThread: Identifiable {
  let root: RenderedComment
  let replies: [RenderedComment]
  var id: Int { root.id }

  @concurrent static func prepare(_ threads: [CommentThread]) async -> [RenderedThread] {
    func render(_ comment: PublicComment) -> RenderedComment {
      RenderedComment(comment: comment, blocks: MarkdownDocument(parsing: comment.bodyMd, style: .comment).blocks)
    }
    return threads.map { RenderedThread(root: render($0.comment), replies: $0.replies.map(render)) }
  }
}

/// 楼中楼两层：楼主，下面缩进的回复
struct CommentThreadView: View {
  let thread: RenderedThread

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      CommentView(comment: thread.root)
      ForEach(thread.replies) { reply in
        CommentView(comment: reply)
          .padding(.leading, 44)
      }
    }
  }
}

struct CommentView: View {
  let comment: RenderedComment

  @Environment(\.locale) private var locale

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      avatar
      VStack(alignment: .leading, spacing: 4) {
        if let author = comment.comment.author {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { name(author) }
            VStack(alignment: .leading, spacing: 2) { name(author) }
          }
        }
        if let replyTo = comment.comment.replyTo {
          Text("Replying to @\(replyTo.login)")
            .font(.app(.footnote))
            .foregroundStyle(.secondary)
        }
        if comment.comment.deleted {
          Text("This comment was deleted by its author.")
            .font(Typography.commentBody)
            .italic()
            .foregroundStyle(.secondary)
        } else {
          MarkdownBlocksView(blocks: comment.blocks)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private func name(_ author: CommentAuthor) -> some View {
    Text(author.displayName)
      .font(.app(.subheadline).weight(.semibold))
    let date = Text(comment.comment.createdAt, format: SiteCalendar.dateStyle(locale: locale))
    Group {
      if comment.comment.editedAt == nil {
        date
      } else {
        Text("\(date) · Edited")
      }
    }
    .font(.app(.footnote).weight(.semibold))
    .foregroundStyle(.secondary)
  }

  @ViewBuilder private var avatar: some View {
    Group {
      if let url = comment.comment.author?.avatarUrl {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Circle().fill(.quaternary)
        }
      } else {
        Circle().fill(.quaternary)
      }
    }
    .frame(width: 32, height: 32)
    // 头像是正圆，不用连续曲率
    .clipShape(.circle)
    .accessibilityHidden(true)
  }
}
