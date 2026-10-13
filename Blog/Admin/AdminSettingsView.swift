import BlogKit
import SwiftUI

/// "后台"里的设置：读者用的文章语言（不用登录），登录后还有翻译模型
struct AdminSettingsView: View {
  @Environment(ReaderSettings.self) private var settings
  @Environment(AdminSession.self) private var session

  var body: some View {
    @Bindable var settings = settings
    Form {
      Section {
        Picker("Article Language", selection: $settings.contentLocale) {
          ForEach(ContentLocale.supported) { locale in
            Text(verbatim: locale.endonym).tag(locale)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } header: {
        Text("Article Language")
      } footer: {
        Text("Posts without a translation in this language are hidden from lists. Opening one shows the original.")
      }
      if session.isSignedIn {
        ModelSettingsSection()
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Settings"))
  }
}

/// 文章翻译、标签翻译各用哪个模型。选了就保存（和网页一样）；保存失败退回原来的选择
private struct ModelSettingsSection: View {
  @Environment(\.adminClient) private var client
  @Environment(AdminSession.self) private var session
  @State private var current: SiteSettings?
  @State private var error: AdminAPIError?

  var body: some View {
    Section {
      if let current {
        picker("文章翻译", value: current.translationModel) { await save(["translationModel": $0]) }
        picker("标签翻译", value: current.tagTranslationModel) { await save(["tagTranslationModel": $0]) }
      } else if error == nil {
        ProgressView()
      }
      if let error {
        AdminErrorBanner(error: error) { Task { await load() } }
      }
    } header: {
      zh("翻译模型")
    } footer: {
      zh("生成译文时用的 Claude 模型。价格是每百万 token 的输入 / 输出（美元）。正在生成的译文不受影响：编辑器在开始时就定下了模型。")
    }
    .task { await load() }
  }

  private func picker(_ title: String, value: String, onChange: @escaping (String) async -> Void) -> some View {
    Picker(selection: Binding(get: { value }, set: { newValue in Task { await onChange(newValue) } })) {
      ForEach(TranslationModelInfo.all) { model in
        VStack(alignment: .leading) {
          zh("\(model.name) · $\(model.inputPrice.formatted()) / $\(model.outputPrice.formatted())")
          zh(model.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(model.id)
      }
      if !TranslationModelInfo.all.contains(where: { $0.id == value }) {
        zh(value).tag(value)
      }
    } label: {
      zh(title)
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      current = try await client.settings()
      error = nil
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func save(_ change: [String: String]) async {
    guard let client, let previous = current else { return }
    // 先改界面（乐观更新），失败再改回来
    var optimistic = previous
    if let model = change["translationModel"] { optimistic.translationModel = model }
    if let model = change["tagTranslationModel"] { optimistic.tagTranslationModel = model }
    current = optimistic
    do {
      current = try await client.updateSettings(change)
      error = nil
    } catch {
      session.handle(error)
      current = previous
      self.error = error
    }
  }
}
