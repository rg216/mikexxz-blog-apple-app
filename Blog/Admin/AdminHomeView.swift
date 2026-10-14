import AuthenticationServices
import BlogKit
import SwiftUI

/// "后台"标签页：没登录时是登录入口和设置；登录后是各个管理页面的目录
struct AdminHomeView: View {
  /// 由 RootView 保管，切换标签页再回来还停在原来的页面
  @Binding var path: NavigationPath

  @Environment(AdminSession.self) private var session

  var body: some View {
    NavigationStack(path: $path) {
      AdminHomeList()
        .navigationTitle(Text("Admin"))
        .navigationDestination(for: AdminRoute.self) { $0.destination }
    }
    // 退出或 session 失效时回到目录，不留在需要登录的页面上
    .onChange(of: session.isSignedIn) { _, signedIn in
      if !signedIn { path = NavigationPath() }
    }
  }
}

private struct AdminHomeList: View {
  @Environment(AdminSession.self) private var session
  private var client: AdminClient? { session.client }
  @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  @State private var signingIn = false
  @State private var signInError: String?
  @State private var pendingComments: Int?

  var body: some View {
    List {
      if session.isSignedIn {
        signedInSections
      } else {
        signInSection
      }
      Section {
        NavigationLink(value: AdminRoute.settings) {
          Label("Settings", systemImage: "gearshape")
        }
      }
    }
    .task(id: session.isSignedIn) {
      if case .checking = session.state { await session.verify() }
      await loadPendingCount()
    }
    .refreshable { await loadPendingCount() }
  }

  private var signInSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        zh("登录后台")
          .font(.headline)
        zh("在网页上用 Passkey 登录并允许这台设备。登录后可以管理文章、译文、标签、评论和媒体库。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if session.expired {
          zh("登录已过期，请重新登录。")
            .font(.subheadline)
            .foregroundStyle(.orange)
        }
        if let signInError {
          zh(signInError)
            .font(.subheadline)
            .foregroundStyle(.red)
        }
      }
      .padding(.vertical, 4)
      Button {
        Task { await signIn() }
      } label: {
        HStack {
          Label { zh("用网页登录") } icon: { Image(systemName: "person.badge.key") }
          if signingIn {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(signingIn)
    }
  }

  @ViewBuilder private var signedInSections: some View {
    Section {
      NavigationLink(value: AdminRoute.posts) {
        Label { zh("文章") } icon: { Image(systemName: "doc.text") }
      }
      NavigationLink(value: AdminRoute.tags) {
        Label { zh("标签") } icon: { Image(systemName: "tag") }
      }
      NavigationLink(value: AdminRoute.comments) {
        LabeledContent {
          if let pendingComments, pendingComments > 0 {
            zh("\(pendingComments) 条待审核")
              .foregroundStyle(.orange)
          }
        } label: {
          Label { zh("评论") } icon: { Image(systemName: "bubble.left.and.bubble.right") }
        }
      }
      NavigationLink(value: AdminRoute.media) {
        Label { zh("媒体库") } icon: { Image(systemName: "photo.on.rectangle") }
      }
    } header: {
      zh("内容")
    }
    Section {
      NavigationLink(value: AdminRoute.status) {
        Label { zh("系统状态") } icon: { Image(systemName: "waveform.path.ecg") }
      }
      NavigationLink(value: AdminRoute.passkeys) {
        Label { zh("Passkey") } icon: { Image(systemName: "person.badge.key") }
      }
    } header: {
      zh("系统")
    }
    Section {
      switch session.state {
      case .signedIn(let info):
        LabeledContent {
          zh(info.user.displayName)
        } label: {
          zh("已登录")
        }
        LabeledContent {
          zh(info.expiresAt.adminFormatted)
        } label: {
          zh("最晚到期")
        }
      case .unverified(let error):
        AdminErrorBanner(error: error) { Task { await session.verify() } }
      default:
        ProgressView()
      }
      Button(role: .destructive) {
        Task { await session.signOut() }
      } label: {
        zh("退出登录")
      }
    } header: {
      zh("账户")
    } footer: {
      zh("闲置 7 天或登录满 30 天后需要重新登录。")
    }
  }

  private func signIn() async {
    signingIn = true
    signInError = nil
    defer { signingIn = false }
    do {
      try await session.signIn(using: webAuthenticationSession)
    } catch {
      signInError = error.message
    }
  }

  private func loadPendingCount() async {
    guard let client else { return }
    pendingComments = try? await client.pendingCommentCount()
  }
}
