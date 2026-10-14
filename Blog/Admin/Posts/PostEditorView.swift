import BlogKit
import SwiftUI

/// 写 / 改一篇文章（原文）。postId 为 nil 是新文章，第一次保存后变成编辑已有的文章
struct PostEditorView: View {
  let postId: Int?

  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var post: AdminPost?
  @State private var loadError: AdminAPIError?
  @State private var form = PostForm()
  @State private var allTags: [AdminTag] = []
  @State private var saving = false
  @State private var saveError: AdminAPIError?
  @State private var savedNote: String?
  @State private var selection: TextSelection?
  @State private var picking: PickTarget?
  @State private var choosingTags = false
  @State private var previewing = false
  @State private var confirmingDelete = false
  @State private var confirmingDiscard = false

  private enum PickTarget: Identifiable {
    case cover, insert
    var id: Self { self }
  }

  private var isNew: Bool { post == nil }
  private var isDirty: Bool { form != (post.map(PostForm.init) ?? PostForm()) }

  var body: some View {
    Group {
      if postId != nil && post == nil {
        if let loadError {
          VStack {
            AdminErrorBanner(error: loadError) { Task { await load() } }.padding()
            Spacer()
          }
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else {
        editor
      }
    }
    .navigationTitle(zh(isNew ? "写文章" : "编辑文章"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar { toolbar }
    .confirmDiscard(when: isDirty, isPresented: $confirmingDiscard) { dismiss() }
    .task { await load() }
    .sheet(item: $picking) { target in
      MediaPickerView { image in
        switch target {
        case .cover: form.cover = image.url
        case .insert: insert(image)
        }
      }
    }
    .sheet(isPresented: $choosingTags) {
      TagPickerView(allTags: allTags, selected: $form.tags)
    }
    .sheet(isPresented: $previewing) {
      PostPreview(title: form.title, content: form.content, images: post?.images ?? [:])
    }
    .confirmationDialog(Text(verbatim: "删除这篇文章？"), isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(role: .destructive) {
        Task { await delete() }
      } label: {
        zh("删除文章和所有译文")
      }
    } message: {
      zh("删除后无法恢复，文章的网址会变成 404。")
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .confirmationAction) {
      Button {
        Task { await save() }
      } label: {
        zh(saving ? "正在保存…" : "保存")
      }
      .disabled(saving || !isDirty)
      .keyboardShortcut("s", modifiers: .command)
    }
    ToolbarItem(placement: .secondaryAction) {
      Button {
        previewing = true
      } label: {
        Label { zh("预览") } icon: { Image(systemName: "eye") }
      }
    }
    if let post {
      ToolbarItem(placement: .secondaryAction) {
        if post.status == .published {
          Link(destination: SiteLinks.postURL(slug: post.slug, locale: post.sourceLocale)) {
            Label { zh("在网页上查看") } icon: { Image(systemName: "safari") }
          }
          .opensLinksInBrowser()
        }
      }
      ToolbarItem(placement: .secondaryAction) {
        Button(role: .destructive) {
          confirmingDelete = true
        } label: {
          Label { zh("删除文章") } icon: { Image(systemName: "trash") }
        }
      }
    }
  }

  private var editor: some View {
    Form {
      if let saveError, saveError.issues.isEmpty || saveError.issue(for: "title") == nil && saveError.issue(for: "slug") == nil {
        AdminErrorBanner(error: saveError)
      }
      if let savedNote {
        Label { zh(savedNote) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
          .font(.subheadline)
      }
      Section {
        field("标题", text: $form.title, issue: "title")
        field("slug（网址）", text: $form.slug, issue: "slug", monospaced: true)
        Picker(selection: $form.status) {
          ForEach(PostStatus.allCases, id: \.self) { status in
            zh(status.label).tag(status)
          }
        } label: {
          zh("状态")
        }
        .pickerStyle(.segmented)
        if let post, let publishedAt = post.publishedAt {
          LabeledContent {
            zh(publishedAt.adminFormatted)
          } label: {
            zh("首次发布")
          }
        }
      } footer: {
        if let post, post.status == .published, form.slug != post.slug {
          zh("改 slug 之后，旧网址 /posts/\(post.slug) 会变成 404。")
            .foregroundStyle(.orange)
        }
      }
      Section {
        if form.tags.isEmpty {
          zh("没有标签").foregroundStyle(.secondary)
        } else {
          zh(form.tags.map { slug in allTags.first { $0.slug == slug }?.name ?? slug }.joined(separator: "、"))
        }
        Button {
          choosingTags = true
        } label: {
          zh("选择标签")
        }
        if let message = saveError?.issues.first(where: { $0.path.hasPrefix("tags") })?.message {
          zh(message).font(.footnote).foregroundStyle(.red)
        }
      } header: {
        zh("标签")
      }
      Section {
        if let cover = form.cover {
          AsyncImage(url: cover) { image in
            image.resizable().scaledToFit()
          } placeholder: {
            Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
          }
          .frame(maxHeight: 200)
          .clipShape(.rect(cornerRadius: 8, style: .continuous))
          Button(role: .destructive) {
            form.cover = nil
          } label: {
            zh("移除头图")
          }
        }
        Button {
          picking = .cover
        } label: {
          zh(form.cover == nil ? "从媒体库选择头图" : "换一张")
        }
      } header: {
        zh("头图")
      } footer: {
        zh("显示在文章页顶部、列表卡片和分享卡片上。")
      }
      Section {
        TextEditor(text: $form.content, selection: $selection)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 360)
          .autocorrectionDisabled()
        Button {
          picking = .insert
        } label: {
          Label { zh("插入图片") } icon: { Image(systemName: "photo.badge.plus") }
        }
      } header: {
        zh("正文（Markdown）")
      } footer: {
        zh("图片地址后面加 #small、#medium 或 #w=320 控制显示宽度；默认是比正文更宽的“大”图。")
      }
      if let post {
        Section {
          ForEach(ContentLocale.supported.filter { $0 != post.sourceLocale }) { locale in
            NavigationLink(value: AdminRoute.translation(postId: post.id, locale: locale)) {
              translationRow(post: post, locale: locale)
            }
          }
        } header: {
          zh("译文")
        } footer: {
          zh(isDirty ? "原文有未保存的修改：先保存，译文页才看得到。" : "原文改过之后，已有的译文会标为过时。")
        }
      }
    }
    .formStyle(.grouped)
  }

  private func translationRow(post: AdminPost, locale: ContentLocale) -> some View {
    let translation = post.translations.first { $0.locale == locale }
    return LabeledContent {
      if let translation {
        VStack(alignment: .trailing, spacing: 2) {
          zh(translation.origin == .machine ? "机器翻译" + (translation.model.map { "（\(TranslationModelInfo.name(of: $0))）" } ?? "") : "人工翻译")
          if translation.outdated {
            zh("原文已更新").foregroundStyle(.orange)
          }
        }
        .font(.footnote)
      } else {
        zh("还没有").foregroundStyle(.secondary)
      }
    } label: {
      zh(locale.adminName)
    }
  }

  private func field(_ title: String, text: Binding<String>, issue: String, monospaced: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      TextField(text: text) { zh(title) }
        .font(monospaced ? .body.monospaced() : .body)
        .autocorrectionDisabled(monospaced)
        #if os(iOS)
          .textInputAutocapitalization(monospaced ? .never : .sentences)
        #endif
      if let message = saveError?.issue(for: issue) {
        zh(message).font(.footnote).foregroundStyle(.red)
      }
    }
  }

  /// 在光标处插入图片的 Markdown（没有光标时加在末尾），描述取媒体库里的
  private func insert(_ image: AdminImage) {
    let snippet = "![\(image.description)](\(image.url.absoluteString))"
    if case .selection(let range) = selection?.indices, range.lowerBound >= form.content.startIndex, range.upperBound <= form.content.endIndex {
      form.content.replaceSubrange(range, with: snippet)
    } else {
      form.content += (form.content.isEmpty || form.content.hasSuffix("\n\n") ? "" : "\n\n") + snippet + "\n"
    }
  }

  private func load() async {
    guard let client else { return }
    allTags = (try? await client.tags()) ?? allTags
    guard let id = post?.id ?? postId else { return }
    do {
      let loaded = try await client.post(id: id)
      // 正在编辑的内容不被重新加载冲掉（从译文页返回时也会走到这里）
      if post == nil || !isDirty { form = PostForm(loaded) }
      post = loaded
      loadError = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      loadError = error
    }
  }

  private func save() async {
    guard let client else { return }
    saving = true
    savedNote = nil
    defer { saving = false }
    let input = PostInput(
      slug: form.slug.trimmingCharacters(in: .whitespaces), title: form.title, contentMd: form.content, status: form.status, tags: form.tags,
      coverImage: .some(form.cover))
    do {
      let saved = if let post { try await client.updatePost(id: post.id, input) } else { try await client.createPost(input) }
      post = saved
      form = PostForm(saved)
      saveError = nil
      savedNote = saved.status == .published ? "已保存，前台页面会在几秒内更新。" : "已保存为草稿。"
    } catch {
      session.handle(error)
      saveError = error
    }
  }

  private func delete() async {
    guard let client, let post else { return }
    do {
      try await client.deletePost(id: post.id)
      self.post = nil
      form = PostForm()
      dismiss()
    } catch {
      session.handle(error)
      saveError = error
    }
  }
}

/// 编辑中的字段（和加载的文章比较，判断有没有未保存的修改）
struct PostForm: Equatable {
  var title = ""
  var slug = ""
  var content = ""
  var status = PostStatus.draft
  var tags: [String] = []
  var cover: URL?

  init() {}

  init(_ post: AdminPost) {
    title = post.title
    slug = post.slug
    content = post.contentMd
    status = post.status
    tags = post.tags.map(\.slug)
    cover = post.cover?.url
  }
}

/// 选标签：只能从已有的标签里选（新标签在"标签"页建）；顺序就是点选的顺序
struct TagPickerView: View {
  let allTags: [AdminTag]
  @Binding var selected: [String]

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(allTags.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.slug.contains(query.lowercased()) }) { tag in
          Button {
            if let index = selected.firstIndex(of: tag.slug) {
              selected.remove(at: index)
            } else {
              selected.append(tag.slug)
            }
          } label: {
            HStack {
              zh(tag.name)
              zh("#\(tag.slug)").foregroundStyle(.secondary).font(.footnote.monospaced())
              Spacer()
              if let index = selected.firstIndex(of: tag.slug) {
                zh("\(index + 1)").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                Image(systemName: "checkmark").foregroundStyle(.tint)
              }
            }
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
      }
      .searchable(text: $query)
      .navigationTitle(zh("选择标签"))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { zh("完成") }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 380, minHeight: 460)
    #endif
  }
}

/// 预览：和读者看到的同一套渲染
struct PostPreview: View {
  let title: String
  let content: String
  let images: [String: ImageMeta]

  @Environment(\.dismiss) private var dismiss
  @State private var document: MarkdownDocument?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          zh(title)
            .font(Typography.articleTitle)
          if let document {
            MarkdownBlocksView(blocks: document.blocks)
          }
        }
        .frame(maxWidth: ReadingLayout.readingWidth, alignment: .leading)
        .padding(ReadingLayout.readingMargin)
        .frame(maxWidth: .infinity)
        .environment(\.markdownImages, images)
        .textSelection(.enabled)
      }
      .navigationTitle(zh("预览"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { zh("完成") }
        }
      }
      .task { document = await Self.parse(content) }
    }
    #if os(macOS)
      .frame(minWidth: 600, minHeight: 600)
    #endif
  }

  @concurrent static func parse(_ content: String) async -> MarkdownDocument {
    MarkdownDocument(parsing: content)
  }
}
