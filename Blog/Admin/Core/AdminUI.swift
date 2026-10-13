import BlogKit
import SwiftUI

/*
 * 后台固定中文，和网页后台一样：API 的报错、状态说明都是写给管理员看的中文，界面跟着用中文才一致。
 * 这些文字用 verbatim，不进字符串表（读者看得到的部分——标签页名称、"设置"里的文章语言——照常本地化）。
 */

/// 后台的中文文字（不进字符串表）。nonisolated：Text 本身不依赖主线程，菜单、工具栏的闭包里也要能用
nonisolated func zh(_ string: String) -> Text {
  Text(verbatim: string)
}

/// 后台各页面的导航目标
enum AdminRoute: Hashable {
  case posts
  case post(id: Int)
  case newPost
  case translation(postId: Int, locale: ContentLocale)
  case tags
  case comments
  case commenters
  case media
  case image(id: Int)
  case status
  case passkeys
  case settings

  @ViewBuilder var destination: some View {
    switch self {
    case .posts: AdminPostsView()
    case .post(let id): PostEditorView(postId: id)
    case .newPost: PostEditorView(postId: nil)
    case .translation(let postId, let locale): TranslationEditorView(postId: postId, locale: locale)
    case .tags: AdminTagsView()
    case .comments: AdminCommentsView()
    case .commenters: CommentersView()
    case .media: MediaLibraryView()
    case .image(let id): ImageDetailView(imageId: id)
    case .status: SystemStatusView()
    case .passkeys: PasskeysView()
    case .settings: AdminSettingsView()
    }
  }
}

/// 错误提示条（不属于某个字段的错误）：服务器的中文说明 + 可选的重试
struct AdminErrorBanner: View {
  let error: AdminAPIError
  var retry: (() -> Void)?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        zh(error.message)
        ForEach(error.issues, id: \.self) { issue in
          zh("\(issue.path)：\(issue.message)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      if let retry {
        Button(action: retry) { zh("重试") }
      }
    }
    .font(.subheadline)
    .padding(12)
    .background(.red.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
  }
}

/// 整页加载：加载中、出错（可重试）、内容。401 交给 AdminSession 处理（回到登录）
struct AdminLoadingView<Value, Content: View>: View {
  let load: (AdminClient) async throws(AdminAPIError) -> Value
  @ViewBuilder let content: (Value, _ reload: @escaping () async -> Void) -> Content

  @Environment(\.adminClient) private var client
  @Environment(AdminSession.self) private var session
  @State private var state: AdminLoadState<Value> = .loading

  var body: some View {
    Group {
      switch state {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let error):
        VStack {
          AdminErrorBanner(error: error) { Task { await reload() } }
            .padding()
          Spacer()
        }
      case .loaded(let value):
        content(value, reload)
      }
    }
    .task { await reload() }
  }

  private func reload() async {
    guard let client else { return }
    do {
      state = .loaded(try await load(client))
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      if case .loaded = state { return }
      state = .failed(error)
    }
  }
}

enum AdminLoadState<Value> {
  case loading
  case loaded(Value)
  case failed(AdminAPIError)
}

/// 状态的小圆点 + 文字（文章的草稿 / 已发布、状态页的 ok / warning…）
struct StatusBadge: View {
  let text: String
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
      zh(text)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
  }
}

extension PostStatus {
  var label: String {
    switch self {
    case .draft: "草稿"
    case .published: "已发布"
    }
  }

  var color: Color {
    switch self {
    case .draft: .orange
    case .published: .green
    }
  }
}

extension ContentLocale {
  /// 后台里语言名用中文（网站的 adminLocaleName）
  var adminName: String {
    switch self {
    case .zh: "中文"
    case .en: "英语"
    case .ja: "日语"
    default: rawValue
    }
  }
}

extension Date {
  /// 后台的时间：站点时区、中文
  var adminFormatted: String {
    formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "zh-Hans"), calendar: SiteCalendar.calendar, timeZone: SiteCalendar.timeZone))
  }
}

extension View {
  /// 有改动没保存时，离开前确认（返回按钮、⌘[）
  func confirmDiscard(when dirty: Bool, isPresented: Binding<Bool>, discard: @escaping () -> Void) -> some View {
    navigationBarBackButtonHidden(dirty)
      .toolbar {
        if dirty {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              isPresented.wrappedValue = true
            } label: {
              Label { zh("返回") } icon: { Image(systemName: "chevron.backward") }
            }
          }
        }
      }
      .confirmationDialog(Text(verbatim: "放弃未保存的修改？"), isPresented: isPresented, titleVisibility: .visible) {
        Button(role: .destructive, action: discard) { zh("放弃修改") }
        Button(role: .cancel) {} label: { zh("继续编辑") }
      }
  }
}
