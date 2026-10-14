import BlogKit
import SwiftUI

/// 评论审核。规则是白名单制：白名单里的人直接显示，其他人的每条都待审核，拉黑的不能评论。
/// 加入白名单会通过他所有待审核的评论，拉黑会拒绝它们
struct AdminCommentsView: View {
  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var status = CommentStatus.pending
  @State private var comments: [AdminComment]?
  @State private var error: AdminAPIError?

  var body: some View {
    List {
      Picker(selection: $status) {
        zh("待审核").tag(CommentStatus.pending)
        zh("已通过").tag(CommentStatus.approved)
        zh("已拒绝").tag(CommentStatus.rejected)
      } label: {
        zh("状态")
      }
      .pickerStyle(.segmented)
      .listRowSeparator(.hidden)
      .rowFont()
      if let error {
        AdminErrorBanner(error: error) { Task { await load() } }
      }
      if let comments {
        if comments.isEmpty {
          zh(status == .pending ? "没有待审核的评论。" : "没有评论。").foregroundStyle(.secondary).rowFont()
        }
        ForEach(comments) { comment in
          AdminCommentRow(comment: comment)
            .swipeActions(edge: .leading) {
              if comment.status != .approved {
                Button { Task { await moderate(comment, .approved) } } label: { Label { zh("通过") } icon: { Image(systemName: "checkmark") } }
                  .tint(.green)
              }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) { Task { await remove(comment) } } label: { Label { zh("删除") } icon: { Image(systemName: "trash") } }
              if comment.status != .rejected {
                Button { Task { await moderate(comment, .rejected) } } label: { Label { zh("拒绝") } icon: { Image(systemName: "xmark") } }
                  .tint(.orange)
              }
            }
            .contextMenu { menu(comment) }
        }
      } else if error == nil {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(zh("评论"))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        NavigationLink(value: AdminRoute.commenters) {
          Label { zh("评论者") } icon: { Image(systemName: "person.2") }
        }
      }
    }
    .task(id: status) { await load() }
    .refreshable { await load() }
  }

  @ViewBuilder private func menu(_ comment: AdminComment) -> some View {
    if comment.status != .approved {
      Button { Task { await moderate(comment, .approved) } } label: { Label { zh("通过") } icon: { Image(systemName: "checkmark") } }
    }
    if comment.status != .rejected {
      Button { Task { await moderate(comment, .rejected) } } label: { Label { zh("拒绝") } icon: { Image(systemName: "xmark") } }
    }
    Divider()
    if comment.author.trust != .trusted {
      Button { Task { await trust(comment.author, .trusted) } } label: {
        Label { zh("把 @\(comment.author.login) 加入白名单") } icon: { Image(systemName: "person.badge.shield.checkmark") }
      }
    }
    if comment.author.trust != .blocked {
      Button(role: .destructive) { Task { await trust(comment.author, .blocked) } } label: {
        Label { zh("拉黑 @\(comment.author.login)") } icon: { Image(systemName: "person.slash") }
      }
    }
    Divider()
    Button(role: .destructive) { Task { await remove(comment) } } label: { Label { zh("删除") } icon: { Image(systemName: "trash") } }
  }

  private func load() async {
    guard let client else { return }
    do {
      comments = try await client.comments(status: status)
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func perform(_ action: (AdminClient) async throws(AdminAPIError) -> Void) async {
    guard let client else { return }
    do {
      try await action(client)
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func moderate(_ comment: AdminComment, _ status: CommentStatus) async {
    await perform { client throws(AdminAPIError) in try await client.moderateComment(id: comment.id, status: status) }
  }

  private func remove(_ comment: AdminComment) async {
    await perform { client throws(AdminAPIError) in try await client.deleteComment(id: comment.id) }
  }

  private func trust(_ commenter: AdminCommenter, _ trust: CommenterTrust) async {
    await perform { client throws(AdminAPIError) in _ = try await client.setCommenterTrust(id: commenter.id, trust: trust) }
  }
}

private struct AdminCommentRow: View {
  let comment: AdminComment

  @State private var blocks: [MarkdownBlock] = []

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      AsyncImage(url: comment.author.avatarUrl) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Circle().fill(.quaternary)
      }
      .frame(width: 32, height: 32)
      .clipShape(.circle)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          zh(comment.author.name ?? comment.author.login).font(.app(.subheadline).weight(.semibold))
          zh("@\(comment.author.login)").font(.app(.footnote)).foregroundStyle(.secondary)
          TrustBadge(trust: comment.author.trust)
        }
        zh("《\(comment.post.title)》 · \(comment.createdAt.adminFormatted)")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
        if let parent = comment.parent {
          zh("回复 @\(parent.login)：\(parent.excerpt)")
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(6)
            .background(.fill.quaternary, in: .rect(cornerRadius: 6, style: .continuous))
        }
        MarkdownBlocksView(blocks: blocks)
          .environment(\.markdownTheme, .comment)
      }
    }
    .padding(.vertical, 4)
    .task(id: comment.bodyMd) { blocks = MarkdownDocument(parsing: comment.bodyMd, style: .comment).blocks }
  }
}

struct TrustBadge: View {
  let trust: CommenterTrust

  var body: some View {
    switch trust {
    case .trusted: StatusBadge(text: "白名单", color: .green)
    case .blocked: StatusBadge(text: "已拉黑", color: .red)
    case .default: EmptyView()
    }
  }
}

/// 评论者：调整信任等级，或按 GitHub 用户名预先加入白名单（对方还没来评论过也可以）
struct CommentersView: View {
  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var commenters: [AdminCommenter]?
  @State private var error: AdminAPIError?
  @State private var login = ""
  @State private var adding = false

  var body: some View {
    List {
      if let error {
        AdminErrorBanner(error: error)
      }
      Section {
        HStack {
          TextField(text: $login) { zh("GitHub 用户名") }
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
            .onSubmit { Task { await add() } }
          Button {
            Task { await add() }
          } label: {
            if adding { ProgressView() } else { zh("加入白名单") }
          }
          .disabled(adding || login.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .rowFont()
      } footer: {
        zh("白名单里的人发评论直接显示，不用审核。").footerFont()
      }
      Section {
        if let commenters {
          if commenters.isEmpty {
            zh("还没有人评论过。").foregroundStyle(.secondary).rowFont()
          }
          ForEach(commenters) { commenter in
            HStack(spacing: 12) {
              AsyncImage(url: commenter.avatarUrl) { image in
                image.resizable().scaledToFill()
              } placeholder: {
                Circle().fill(.quaternary)
              }
              .frame(width: 28, height: 28)
              .clipShape(.circle)
              .accessibilityHidden(true)
              VStack(alignment: .leading) {
                zh(commenter.name ?? commenter.login)
                zh("@\(commenter.login)").font(.app(.footnote)).foregroundStyle(.secondary)
              }
              Spacer()
              Picker(selection: Binding(get: { commenter.trust }, set: { trust in Task { await setTrust(commenter, trust) } })) {
                zh("需审核").tag(CommenterTrust.default)
                zh("白名单").tag(CommenterTrust.trusted)
                zh("已拉黑").tag(CommenterTrust.blocked)
              } label: {
                zh("信任等级")
              }
              .labelsHidden()
              .fixedSize()
            }
            .rowFont()
          }
        } else {
          ProgressView().frame(maxWidth: .infinity)
        }
      } header: {
        zh("评论者")
      }
    }
    .navigationTitle(zh("评论者"))
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    guard let client else { return }
    do {
      commenters = try await client.commenters()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func setTrust(_ commenter: AdminCommenter, _ trust: CommenterTrust) async {
    guard let client else { return }
    do {
      _ = try await client.setCommenterTrust(id: commenter.id, trust: trust)
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func add() async {
    guard let client else { return }
    adding = true
    defer { adding = false }
    do {
      _ = try await client.addTrustedCommenter(login: login.trimmingCharacters(in: .whitespaces))
      login = ""
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}
