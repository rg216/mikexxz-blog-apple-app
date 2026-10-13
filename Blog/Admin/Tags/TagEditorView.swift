import BlogKit
import SwiftUI

/// 新建 / 编辑一个标签。每种语言的译名都必填（标签很短，一次填齐的成本很低，而前台每种语言都会显示它）；
/// 可以让大模型给出译名，只填进输入框，保存后才生效
struct TagEditorView: View {
  let target: TagEditorTarget
  let allTags: [AdminTag]
  let onChange: () async -> Void

  @Environment(\.adminClient) private var client
  @Environment(AdminSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var slug = ""
  @State private var translations: [String: String] = [:]
  @State private var error: AdminAPIError?
  @State private var saving = false
  @State private var translating = false
  @State private var translateNote: String?
  @State private var tagModel: String?
  @State private var mergeInto: Int?
  @State private var confirmingMerge = false

  private var original: AdminTag? { target.tag }

  private var isDirty: Bool {
    guard let original else { return !name.isEmpty || !slug.isEmpty || translations.values.contains { !$0.isEmpty } }
    return name != original.name || slug != original.slug || AdminTag.translationLocales.contains { translations[$0.rawValue, default: ""] != original.translations[$0.rawValue, default: ""] }
  }

  var body: some View {
    NavigationStack {
      Form {
        if let error, error.issues.isEmpty {
          AdminErrorBanner(error: error)
        }
        Section {
          field("名称（中文）", text: $name, issue: "name")
          field("slug", text: $slug, issue: "slug", monospaced: true)
          if let original, slug != original.slug {
            Label {
              zh("旧的标签页网址 /tags/\(original.slug) 会失效（不做跳转）。")
            } icon: {
              Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(.orange)
          }
        } footer: {
          zh("slug 用在标签页的网址里：小写字母、数字，用单个连字符分隔。")
        }
        Section {
          ForEach(AdminTag.translationLocales) { locale in
            field("\(locale.adminName)名称", text: binding(for: locale), issue: "translations.\(locale.rawValue)")
          }
          Button {
            Task { await translate() }
          } label: {
            HStack {
              Label {
                zh(tagModel.map { "用 \(TranslationModelInfo.name(of: $0)) 翻译" } ?? "用大模型翻译")
              } icon: {
                Image(systemName: "sparkles")
              }
              if translating {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(translating || name.trimmingCharacters(in: .whitespaces).isEmpty || tagModel == nil)
          if let translateNote {
            zh(translateNote)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          zh("译名")
        } footer: {
          zh("翻译结果只填进输入框，看过、保存后才生效。站上已有的译名会作为参考，风格保持一致。")
        }
        if let original {
          mergeSection(original)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(zh(original == nil ? "新建标签" : "编辑标签"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { zh("取消") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await save() }
          } label: {
            zh(saving ? "正在保存…" : "保存")
          }
          .disabled(saving || !isDirty)
          .keyboardShortcut("s", modifiers: .command)
        }
      }
      .interactiveDismissDisabled(isDirty)
      .confirmationDialog(Text(verbatim: "合并标签？"), isPresented: $confirmingMerge, titleVisibility: .visible) {
        Button(role: .destructive) {
          Task { await merge() }
        } label: {
          zh("合并")
        }
      } message: {
        if let original, let into = allTags.first(where: { $0.id == mergeInto }) {
          zh("用到“\(original.name)”的 \(original.postCount) 篇文章改用“\(into.name)”，然后删除“\(original.name)”。")
        }
      }
    }
    .onAppear(perform: fill)
    .task { await loadModel() }
    #if os(macOS)
      .frame(minWidth: 460, minHeight: 520)
    #endif
  }

  private func mergeSection(_ original: AdminTag) -> some View {
    Section {
      Picker(selection: $mergeInto) {
        zh("选择标签").tag(Int?.none)
        ForEach(allTags.filter { $0.id != original.id }) { tag in
          zh(tag.name).tag(Int?.some(tag.id))
        }
      } label: {
        zh("合并到")
      }
      Button(role: .destructive) {
        confirmingMerge = true
      } label: {
        zh("合并")
      }
      .disabled(mergeInto == nil || isDirty)
    } header: {
      zh("合并")
    } footer: {
      zh(isDirty ? "先保存或放弃当前的修改再合并。" : "意思重复的标签合成一个：用到这个标签的文章改用选中的标签（同时有两个的只保留后者），然后删除这个标签。")
    }
  }

  private func field(_ title: String, text: Binding<String>, issue: String, monospaced: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(text: text) { zh(title) }
        .font(monospaced ? .body.monospaced() : .body)
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
      if let message = error?.issue(for: issue) {
        zh(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private func binding(for locale: ContentLocale) -> Binding<String> {
    Binding(get: { translations[locale.rawValue, default: ""] }, set: { translations[locale.rawValue] = $0 })
  }

  private func fill() {
    guard let original, name.isEmpty, slug.isEmpty else { return }
    name = original.name
    slug = original.slug
    translations = original.translations
  }

  private func loadModel() async {
    guard let client else { return }
    if let config = try? await client.translationConfig() {
      tagModel = config.available ? config.tagModel : nil
      if !config.available { translateNote = "大模型翻译暂时不可用（服务器没有配置，或限流服务连不上）。" }
    }
  }

  private func translate() async {
    guard let client else { return }
    translating = true
    defer { translating = false }
    do {
      let result = try await client.translateTag(name: name.trimmingCharacters(in: .whitespaces), slug: slug.trimmingCharacters(in: .whitespaces))
      for locale in AdminTag.translationLocales {
        if let value = result.translations[locale.rawValue] { translations[locale.rawValue] = value }
      }
      translateNote = "由 \(TranslationModelInfo.name(of: result.model)) 翻译，用了 \(result.usage.inputTokens + result.usage.outputTokens) 个 token。"
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func save() async {
    guard let client else { return }
    saving = true
    defer { saving = false }
    let filled = Dictionary(uniqueKeysWithValues: AdminTag.translationLocales.map { ($0.rawValue, translations[$0.rawValue, default: ""].trimmingCharacters(in: .whitespaces)) })
    let input = TagInput(slug: slug.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces), translations: filled)
    do {
      if let original {
        _ = try await client.updateTag(id: original.id, input)
      } else {
        _ = try await client.createTag(input)
      }
      await onChange()
      dismiss()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func merge() async {
    guard let client, let original, let mergeInto else { return }
    do {
      _ = try await client.mergeTag(id: original.id, into: mergeInto)
      await onChange()
      dismiss()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}
