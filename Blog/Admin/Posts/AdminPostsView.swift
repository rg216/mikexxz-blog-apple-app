import BlogKit
import SwiftUI

/// 全部文章（含草稿），按更新时间倒序；每篇标出各语言译文的状态
struct AdminPostsView: View {
  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var posts: [AdminPost]?
  @State private var error: AdminAPIError?
  @State private var filter: PostStatus?
  @State private var query = ""

  private var visible: [AdminPost] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    return (posts ?? []).filter { post in
      (filter == nil || post.status == filter)
        && (trimmed.isEmpty || post.title.localizedStandardContains(trimmed) || post.slug.contains(trimmed.lowercased()))
    }
  }

  var body: some View {
    content
      .navigationTitle(zh("文章"))
      .searchable(text: $query, prompt: Text(verbatim: "标题或 slug"))
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink(value: AdminRoute.newPost) {
            Label { zh("写文章") } icon: { Image(systemName: "square.and.pencil") }
          }
        }
        ToolbarItem(placement: .secondaryAction) {
          Picker(selection: $filter) {
            zh("全部").tag(PostStatus?.none)
            zh("草稿").tag(PostStatus?.some(.draft))
            zh("已发布").tag(PostStatus?.some(.published))
          } label: {
            Label { zh("筛选") } icon: { Image(systemName: "line.3.horizontal.decrease") }
          }
        }
      }
      // 编辑页里保存、删除之后 revision 会变：据此重新加载（只靠 onAppear 不可靠，返回时它不一定触发）
      .task(id: session.revision) { await load() }
      .refreshable { await load() }
  }

  @ViewBuilder private var content: some View {
    if let posts {
      List {
        if let error {
          AdminErrorBanner(error: error)
        }
        if posts.isEmpty {
          zh("还没有文章。").foregroundStyle(.secondary).rowFont()
        }
        ForEach(visible) { post in
          NavigationLink(value: AdminRoute.post(id: post.id)) {
            AdminPostRow(post: post)
          }
          .accessibilityIdentifier("admin-post-row")
        }
      }
    } else if let error {
      VStack {
        AdminErrorBanner(error: error) { Task { await load() } }.padding()
        Spacer()
      }
    } else {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      posts = try await client.posts()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}

private struct AdminPostRow: View {
  let post: AdminPost

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      zh(post.title)
        .font(.app(.headline))
      HStack(spacing: 12) {
        StatusBadge(text: post.status.label, color: post.status.color)
        zh("更新于 \(post.updatedAt.adminFormatted)")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
      }
      TranslationBadges(post: post)
    }
    .padding(.vertical, 4)
  }
}

/// 各语言译文的状态：缺 / 人工 / 机器，原文改过之后标"过时"
struct TranslationBadges: View {
  let post: AdminPost

  var body: some View {
    HStack(spacing: 6) {
      ForEach(ContentLocale.supported.filter { $0 != post.sourceLocale }) { locale in
        badge(locale)
      }
    }
    .font(.app(.caption2).weight(.semibold))
  }

  @ViewBuilder private func badge(_ locale: ContentLocale) -> some View {
    let translation = post.translations.first { $0.locale == locale }
    let (text, color): (String, Color) =
      switch translation {
      case nil: ("缺\(locale.adminName)", .secondary)
      case .some(let t) where t.outdated: ("\(locale.adminName) · 过时", .orange)
      case .some(let t): ("\(locale.adminName) · \(t.origin == .machine ? "机器" : "人工")", .green)
      }
    zh(text)
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.12), in: .capsule)
  }
}
