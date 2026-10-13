import BlogKit
import SwiftUI

/// 登录后台用的 Passkey：改名、删除。添加新的 Passkey 要在网页上做——Passkey 绑定网站的域名，
/// App 里注册需要 Associated Domains（见网站 CLAUDE.md "安全"）
struct PasskeysView: View {
  @Environment(\.adminClient) private var client
  @Environment(AdminSession.self) private var session
  @State private var passkeys: [Passkey]?
  @State private var error: AdminAPIError?
  @State private var renaming: Passkey?
  @State private var newName = ""
  @State private var deleting: Passkey?

  var body: some View {
    List {
      if let error {
        AdminErrorBanner(error: error)
      }
      if let passkeys {
        ForEach(passkeys) { passkey in
          VStack(alignment: .leading, spacing: 4) {
            zh(passkey.name).font(.headline)
            zh(passkey.deviceType == "multiDevice" ? "可同步（如 iCloud 钥匙串）" : "绑定单台设备（如硬件密钥）")
              .font(.footnote).foregroundStyle(.secondary)
            zh("添加于 \(passkey.createdAt.adminFormatted)" + (passkey.lastUsedAt.map { " · 最近使用 \($0.adminFormatted)" } ?? ""))
              .font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
          .swipeActions {
            Button(role: .destructive) { deleting = passkey } label: { Label { zh("删除") } icon: { Image(systemName: "trash") } }
            Button {
              newName = passkey.name
              renaming = passkey
            } label: {
              Label { zh("改名") } icon: { Image(systemName: "pencil") }
            }
          }
          .contextMenu {
            Button {
              newName = passkey.name
              renaming = passkey
            } label: {
              Label { zh("改名") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) { deleting = passkey } label: { Label { zh("删除") } icon: { Image(systemName: "trash") } }
          }
        }
        Section {
          Link(destination: AppConfiguration.siteURL.appending(path: "admin/settings")) {
            Label { zh("在网页上添加 Passkey") } icon: { Image(systemName: "safari") }
          }
          .opensLinksInBrowser()
        } footer: {
          zh("Passkey 绑定网站的域名，要在网页上注册。不能删除最后一个 Passkey，否则就无法登录了。")
        }
      } else if error == nil {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(zh("Passkey"))
    .task { await load() }
    .alert(Text(verbatim: "Passkey 名称"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { passkey in
      TextField(text: $newName) { zh("名称") }
      Button { Task { await rename(passkey) } } label: { zh("保存") }
      Button(role: .cancel) {} label: { zh("取消") }
    }
    .confirmationDialog(
      Text(verbatim: "删除这个 Passkey？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible,
      presenting: deleting
    ) { passkey in
      Button(role: .destructive) { Task { await delete(passkey) } } label: { zh("删除“\(passkey.name)”") }
    } message: { _ in
      zh("删除后，这个 Passkey 所在的设备就不能再登录后台了。")
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      passkeys = try await client.passkeys()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func rename(_ passkey: Passkey) async {
    guard let client else { return }
    do {
      _ = try await client.renamePasskey(id: passkey.id, name: newName.trimmingCharacters(in: .whitespaces))
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func delete(_ passkey: Passkey) async {
    guard let client else { return }
    do {
      try await client.deletePasskey(id: passkey.id)
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}
