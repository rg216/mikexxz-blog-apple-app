import BlogKit
import SwiftUI

/// "后台"里的设置：读者用的文章语言（不用登录），登录后还有翻译模型和生成头图
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
        .rowFont()
      } header: {
        Text("Article Language")
      } footer: {
        Text("Posts without a translation in this language are hidden from lists. Opening one shows the original.").footerFont()
      }
      if session.isSignedIn {
        SiteSettingsSections()
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Settings"))
  }
}

/// 服务器上的运行时设置：翻译模型、生成头图。选了就保存（和网页一样）；保存失败退回原来的选择。
/// 头图风格是一段长文字，要按"保存"：边打字边存会把半句话发给图像模型
private struct SiteSettingsSections: View {
  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var current: SiteSettings?
  @State private var error: AdminAPIError?
  /// 正在编辑的头图风格；nil 表示没改过，显示已保存的
  @State private var styleDraft: String?
  @State private var savingStyle = false
  /// 保存风格的错误显示在风格那一节里（离按钮近）
  @State private var styleError: AdminAPIError?

  var body: some View {
    Section {
      if let current {
        picker("文章翻译", value: current.translationModel, options: Self.claudeModels) { await save(["translationModel": $0]) }
        picker("标签翻译", value: current.tagTranslationModel, options: Self.claudeModels) { await save(["tagTranslationModel": $0]) }
      } else if error == nil {
        ProgressView()
      }
      if let error {
        AdminErrorBanner(error: error) { Task { await load() } }
      }
    } header: {
      zh("翻译模型")
    } footer: {
      zh("生成译文时用的 Claude 模型。价格是每百万 token 的输入 / 输出（美元）。正在生成的译文不受影响：编辑器在开始时就定下了模型。").footerFont()
    }
    .task { await load() }

    // API 还没更新（没有这几项设置）时不显示
    if let current, let promptModel = current.coverPromptModel, let imageModel = current.coverImageModel, let quality = current.coverImageQuality,
      let style = current.coverStyle
    {
      Section {
        picker("画面描述", value: promptModel, options: Self.claudeModels) { await save(["coverPromptModel": $0]) }
        picker("出图模型", value: imageModel, options: Self.imageModels) { await save(["coverImageModel": $0]) }
        picker("画质", value: quality, options: Self.qualities) { await save(["coverImageQuality": $0]) }
      } header: {
        zh("生成头图")
      } footer: {
        zh("文章编辑器里“头图”的“生成”：先由 Claude 读文章写画面描述（输出很短：Sonnet 5.5 足够，Haiku 5.5 更便宜），再由 OpenAI GPT Image 出图（需要 API 项目设置 OPENAI_API_KEY）。两个出图模型的 token 单价相同；画质越高，token 越多、越慢。")
          .footerFont()
      }
      styleSection(saved: style)
    }
  }

  private func styleSection(saved: String) -> some View {
    let value = styleDraft ?? saved
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let dirty = styleDraft != nil && trimmed != saved
    return Section {
      if let styleError {
        AdminErrorBanner(error: styleError)
      }
      TextEditor(text: Binding(get: { value }, set: { styleDraft = $0 }))
        .font(.app(.callout, design: .monospaced))
        .frame(minHeight: 220)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        .accessibilityLabel(zh("头图风格"))
        .accessibilityIdentifier("cover-style")
      HStack {
        Button {
          Task { await saveStyle(trimmed) }
        } label: {
          zh(savingStyle ? "正在保存…" : "保存")
        }
        .disabled(!dirty || trimmed.isEmpty || trimmed.count > CoverOptions.styleMaxLength || savingStyle)
        Spacer()
        // 只填进输入框，按"保存"才生效
        Button {
          styleDraft = CoverOptions.defaultStyle
        } label: {
          zh("恢复默认")
        }
        .disabled(trimmed == CoverOptions.defaultStyle)
      }
      .buttonStyle(.borderless)
      .rowFont()
    } header: {
      zh("头图风格")
    } footer: {
      zh("英文。每次出图都放在画面描述前面，Claude 写描述时也照着它。头图三种语言共用，所以默认不放中文、日文。\(value.count) / \(CoverOptions.styleMaxLength) 字")
        .foregroundStyle(value.count > CoverOptions.styleMaxLength ? .red : .secondary)
        .footerFont()
    }
  }

  private struct Option: Identifiable {
    let id: String
    let title: String
    let detail: String
  }

  private static let claudeModels = TranslationModelInfo.all.map {
    Option(id: $0.id, title: "\($0.name) · $\($0.inputPrice.formatted()) / $\($0.outputPrice.formatted())", detail: $0.summary)
  }
  private static let imageModels = CoverOptions.imageModels.map { Option(id: $0.id, title: $0.name, detail: $0.summary) }
  private static let qualities = CoverOptions.qualities.map { Option(id: $0.id, title: $0.name, detail: $0.summary) }

  private func picker(_ title: String, value: String, options: [Option], onChange: @escaping (String) async -> Void) -> some View {
    Picker(selection: Binding(get: { value }, set: { newValue in Task { await onChange(newValue) } })) {
      ForEach(options) { option in
        VStack(alignment: .leading) {
          zh(option.title)
          zh(option.detail)
            .font(.app(.caption))
            .foregroundStyle(.secondary)
        }
        .tag(option.id)
      }
      // 网站加了 App 不认识的选项
      if !options.contains(where: { $0.id == value }) {
        zh(value).tag(value)
      }
    } label: {
      zh(title)
    }
    .rowFont()
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
    current = previous.applying(change)
    do {
      current = try await client.updateSettings(change)
      error = nil
    } catch {
      session.handle(error)
      current = previous
      self.error = error
    }
  }

  private func saveStyle(_ style: String) async {
    guard let client, current != nil else { return }
    savingStyle = true
    defer { savingStyle = false }
    do {
      current = try await client.updateSettings(["coverStyle": style])
      styleDraft = nil
      styleError = nil
    } catch {
      session.handle(error)
      styleError = error
    }
  }
}
