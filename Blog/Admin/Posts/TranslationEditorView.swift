import BlogKit
import SwiftUI

/// 一篇文章某种语言的译文：手工编辑，或用大模型生成后过目再保存。
///
/// 机器译文和人工译文的区别（网站的规则）：保存时标题和正文都和生成结果一字不差，才记为机器译文（服务器会再做一次结构校验，
/// 有错误就拒绝保存）；改过任何一个字就是人工译文
struct TranslationEditorView: View {
  let postId: Int
  let locale: ContentLocale

  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var post: AdminPost?
  @State private var saved: AdminTranslation?
  @State private var config: TranslationConfig?
  @State private var loadError: AdminAPIError?
  @State private var title = ""
  @State private var content = ""
  /// 生成完成时的结果：保存时比较，判断是不是原样的机器译文
  @State private var generated: (title: String, content: String, model: String, sourceHash: String)?
  @State private var generation = TranslationGeneration()
  @State private var generationTask: Task<Void, Never>?
  @State private var saveError: AdminAPIError?
  @State private var savedNote: String?
  @State private var saving = false
  @State private var confirmingDiscard = false
  @State private var confirmingReplace = false
  @State private var confirmingDelete = false
  @State private var confirmingHalfTranslated = false

  private var isGenerating: Bool { generation.phase == .running }
  private var isDirty: Bool { title != (saved?.title ?? "") || content != (saved?.contentMd ?? "") }
  private var isUnmodifiedMachineOutput: Bool {
    guard let generated, let post else { return false }
    return generated.title == title && generated.content == content && generated.sourceHash == post.sourceHash
  }

  var body: some View {
    Group {
      if let post {
        editor(post)
      } else if let loadError {
        VStack {
          AdminErrorBanner(error: loadError) { Task { await load() } }.padding()
          Spacer()
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle(zh("\(locale.adminName)译文"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar { toolbar }
    .confirmDiscard(when: isDirty || isGenerating, isPresented: $confirmingDiscard) {
      generationTask?.cancel()
      dismiss()
    }
    .task { await load() }
    .onDisappear { generationTask?.cancel() }
    .confirmationDialog(Text(verbatim: "替换编辑器里的内容？"), isPresented: $confirmingReplace, titleVisibility: .visible) {
      Button(role: .destructive) { startGeneration(resume: false) } label: { zh("生成并替换") }
    } message: {
      zh(saved?.origin == .human ? "现在的译文是人工翻译或修改过的，生成的结果会替换它（保存前不会影响读者）。" : "生成的结果会替换编辑器里的内容（保存前不会影响读者）。")
    }
    .confirmationDialog(Text(verbatim: "删除这篇译文？"), isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(role: .destructive) { Task { await deleteTranslation() } } label: { zh("删除译文") }
    } message: {
      zh("删除后，\(locale.adminName)读者打开这篇文章会看到原文。")
    }
    .confirmationDialog(Text(verbatim: "有一项和原文完全相同"), isPresented: $confirmingHalfTranslated, titleVisibility: .visible) {
      Button { Task { await save(confirmed: true) } } label: { zh("仍然保存") }
    } message: {
      zh("标题或正文和原文一样。产品名之类的标题本来就可能相同；如果是忘了翻译，请先改好。")
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
      Button {
        Task { await save(confirmed: false) }
      } label: {
        zh(saving ? "正在保存…" : "保存")
      }
      .disabled(saving || isGenerating || !isDirty || title.trimmingCharacters(in: .whitespaces).isEmpty)
      .keyboardShortcut("s", modifiers: .command)
    }
    if saved != nil {
      ToolbarItem(placement: .secondaryAction) {
        Button(role: .destructive) {
          confirmingDelete = true
        } label: {
          Label { zh("删除译文") } icon: { Image(systemName: "trash") }
        }
        .disabled(isGenerating)
      }
    }
  }

  private func editor(_ post: AdminPost) -> some View {
    Form {
      if let saveError {
        AdminErrorBanner(error: saveError)
      }
      if let savedNote {
        Label { zh(savedNote) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
          .font(.subheadline)
      }
      statusSection(post)
      generationSection(post)
      if isGenerating {
        progressSection
      } else {
        Section {
          TextField(text: $title) { zh("标题") }
          TextEditor(text: $content)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 360)
            .autocorrectionDisabled()
        } header: {
          zh("译文")
        } footer: {
          if generated != nil {
            zh(isUnmodifiedMachineOutput ? "未经修改的机器译文：保存后标注“机器翻译”。" : "改过生成结果：保存后记为人工译文。")
          }
        }
      }
      Section {
        DisclosureGroup {
          VStack(alignment: .leading, spacing: 8) {
            zh(post.title).font(.headline)
            zh(post.contentMd)
              .font(.system(.footnote, design: .monospaced))
              .textSelection(.enabled)
          }
        } label: {
          zh("原文（\(post.sourceLocale.adminName)）")
        }
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder private func statusSection(_ post: AdminPost) -> some View {
    Section {
      if let saved {
        LabeledContent {
          zh(saved.origin == .machine ? "机器翻译" + (saved.model.map { "（\($0)）" } ?? "") : "人工翻译")
        } label: {
          zh("已保存的译文")
        }
        LabeledContent { zh(saved.translatedAt.adminFormatted) } label: { zh("保存于") }
        if saved.outdated {
          Label { zh("原文在这之后改过，译文可能已经过时。") } icon: { Image(systemName: "clock.badge.exclamationmark") }
            .foregroundStyle(.orange)
            .font(.subheadline)
        }
      } else {
        zh("还没有\(locale.adminName)译文：保存之前，\(locale.adminName)读者打开这篇文章看到的是原文。")
          .foregroundStyle(.secondary)
          .font(.subheadline)
      }
      if post.status == .draft {
        zh("文章还是草稿：译文保存后，要等文章发布才对读者可见。")
          .foregroundStyle(.secondary)
          .font(.footnote)
      }
    }
  }

  @ViewBuilder private func generationSection(_ post: AdminPost) -> some View {
    Section {
      if let config {
        Button {
          if isGenerating {
            generationTask?.cancel()
          } else if !title.isEmpty || !content.isEmpty {
            confirmingReplace = true
          } else {
            startGeneration(resume: false)
          }
        } label: {
          Label {
            zh(isGenerating ? "停止生成" : "用 \(TranslationModelInfo.name(of: config.model)) 生成译文")
          } icon: {
            Image(systemName: isGenerating ? "stop.circle" : "sparkles")
          }
        }
        .disabled(!config.available)
        if !config.available {
          zh(config.reason == "rate_limiter_unavailable" ? "限流服务（Redis）连不上：翻译按次计费，限不了流就不放行。" : "服务器没有配置 ANTHROPIC_API_KEY（和 REDIS_URL），生成不可用。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if case .failed(let message) = generation.phase {
          Label { zh(message) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            .font(.subheadline)
          if generation.canResume {
            Button {
              startGeneration(resume: true)
            } label: {
              zh("从第 \(generation.segments.count + 1) 段继续（已完成的不重新生成）")
            }
          }
        }
        if generation.phase == .finished {
          zh("生成完成：\(generation.combinedModel)，输入 \(generation.usage.inputTokens) / 输出 \(generation.usage.outputTokens) token，缓存命中 \(generation.usage.cacheReadInputTokens)。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } else {
        ProgressView()
      }
    } header: {
      zh("大模型翻译")
    } footer: {
      zh("生成结果先放进编辑器，看过、保存后才对读者可见。正文按段逐个生成，一次只发一个请求（共享提示缓存）。")
    }
  }

  private var progressSection: some View {
    Section {
      ProgressView(value: Double(generation.step), total: Double(max(generation.totalSteps, 1))) {
        zh(generation.step == 0 ? "正在翻译标题…" : "正在翻译正文：第 \(generation.step) / \(generation.totalSteps - 1) 段")
      }
      if generation.thinking {
        zh("（模型思考中…）").foregroundStyle(.secondary)
      }
      if !generation.streaming.isEmpty {
        zh(String(generation.streaming.suffix(1500)))
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    } header: {
      zh("正在生成")
    }
  }

  private func startGeneration(resume: Bool) {
    guard let client, let post, let config else { return }
    savedNote = nil
    saveError = nil
    generationTask = Task {
      await generation.run(client: client, post: post, locale: locale, model: config.model, resume: resume)
      if generation.phase == .finished, let generatedTitle = generation.title {
        let body = generation.body
        title = generatedTitle
        content = body
        generated = (generatedTitle, body, generation.combinedModel, post.sourceHash)
      }
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      let loadedPost = try await client.post(id: postId)
      let loadedTranslation = try await client.translation(postId: postId, locale: locale)
      post = loadedPost
      saved = loadedTranslation
      title = loadedTranslation?.title ?? ""
      content = loadedTranslation?.contentMd ?? ""
      config = try await client.translationConfig()
      loadError = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      loadError = error
    }
  }

  private func save(confirmed: Bool) async {
    guard let client, let post else { return }
    // 译文没有草稿状态：拦下"还是原文"的内容（复制原文后顺手保存）
    let sameTitle = title.trimmingCharacters(in: .whitespaces) == post.title.trimmingCharacters(in: .whitespaces)
    let sameBody = content == post.contentMd
    if sameTitle && sameBody {
      saveError = AdminAPIError(kind: .server, message: "标题和正文都和原文相同，还没有翻译。")
      return
    }
    if (sameTitle || sameBody) && !confirmed {
      confirmingHalfTranslated = true
      return
    }
    saving = true
    defer { saving = false }
    let machine = isUnmodifiedMachineOutput ? generated?.model : nil
    let input = TranslationInput(title: title, contentMd: content, sourceHash: post.sourceHash, generatedModel: machine)
    do {
      let result = try await client.saveTranslation(postId: postId, locale: locale, input)
      saved = result
      title = result.title
      content = result.contentMd
      generated = nil
      saveError = nil
      savedNote = result.origin == .machine ? "已保存为机器译文。" : "已保存为人工译文。"
    } catch {
      session.handle(error)
      saveError = error
    }
  }

  private func deleteTranslation() async {
    guard let client else { return }
    do {
      try await client.deleteTranslation(postId: postId, locale: locale)
      saved = nil
      title = ""
      content = ""
      generated = nil
      savedNote = "已删除译文。"
    } catch {
      session.handle(error)
      saveError = error
    }
  }
}
