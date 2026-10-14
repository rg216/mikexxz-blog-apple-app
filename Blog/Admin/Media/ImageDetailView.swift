import BlogKit
import SwiftUI

/// 一张图片：大图、文件名和描述（插入文章时默认的替代文本）、文件夹、被哪些文章引用、删除
struct ImageDetailView: View {
  let imageId: Int

  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @Environment(\.dismiss) private var dismiss
  @State private var detail: AdminImageDetail?
  @State private var folders: [MediaFolder] = []
  @State private var filename = ""
  @State private var description = ""
  @State private var error: AdminAPIError?
  @State private var saving = false
  @State private var confirmingDelete = false
  @State private var copied: String?

  var body: some View {
    Group {
      if let detail {
        form(detail)
      } else if let error {
        VStack {
          AdminErrorBanner(error: error) { Task { await load() } }.padding()
          Spacer()
        }
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .navigationTitle(zh(detail?.image.filename ?? "图片"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task { await load() }
    .confirmationDialog(Text(verbatim: "删除这张图片？"), isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(role: .destructive) {
        Task { await delete() }
      } label: {
        zh((detail?.posts.isEmpty ?? true) ? "删除" : "仍然删除")
      }
    } message: {
      if let detail, !detail.posts.isEmpty {
        zh("这些文章里的图片会显示不出来：\(detail.posts.map { "《\($0.title)》" }.joined(separator: "、"))")
      } else {
        zh("原图和各尺寸版本都会从存储里删除。")
      }
    }
  }

  private func form(_ detail: AdminImageDetail) -> some View {
    let image = detail.image
    return Form {
      if let error {
        AdminErrorBanner(error: error)
      }
      Section {
        RemoteImage(url: image.url, meta: image.meta)
          .aspectRatio(image.meta.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1, contentMode: .fit)
          .frame(maxHeight: 420)
          .frame(maxWidth: .infinity)
      }
      Section {
        Group {
        TextField(text: $filename) { zh("文件名") }
        TextField(text: $description, axis: .vertical) { zh("描述（替代文本）") }
          .lineLimit(2...5)
        Button {
          Task { await save() }
        } label: {
          zh(saving ? "正在保存…" : "保存")
        }
        .disabled(saving || (filename == image.filename && description == image.description))
        }
        .rowFont()
      } footer: {
        zh("描述是插入文章时默认的替代文本，读屏软件会读出它；也用作头图的 alt。").footerFont()
      }
      Section {
        Group {
        Picker(selection: Binding(get: { image.folderId }, set: { id in Task { await move(to: id) } })) {
          zh("不归入文件夹").tag(Int?.none)
          ForEach(folders) { folder in
            zh(folder.name).tag(Int?.some(folder.id))
          }
        } label: {
          zh("文件夹")
        }
        LabeledContent { zh(sizeText(image)) } label: { zh("尺寸") }
        LabeledContent { zh(image.size.formatted(.byteCount(style: .file))) } label: { zh("大小") }
        LabeledContent { zh(image.contentType) } label: { zh("格式") }
        if !image.variants.isEmpty {
          LabeledContent { zh(image.variants.map { "\($0)w" }.joined(separator: "、")) } label: { zh("尺寸版本") }
        }
        LabeledContent { zh(image.createdAt.adminFormatted) } label: { zh("上传于") }
        }
        .rowFont()
      }
      Section {
        Group {
        Button {
          copy(image.url.absoluteString, "已复制地址")
        } label: {
          Label { zh("复制地址") } icon: { Image(systemName: "link") }
        }
        Button {
          copy("![\(image.description)](\(image.url.absoluteString))", "已复制 Markdown")
        } label: {
          Label { zh("复制 Markdown") } icon: { Image(systemName: "doc.on.doc") }
        }
        }
        .rowFont()
        if let copied {
          zh(copied).font(.app(.footnote)).foregroundStyle(.secondary)
        }
      }
      Section {
        if detail.posts.isEmpty {
          zh("没有文章引用它。").foregroundStyle(.secondary).rowFont()
        }
        ForEach(detail.posts) { post in
          NavigationLink(value: AdminRoute.post(id: post.id)) {
            HStack {
              zh(post.title)
              Spacer()
              StatusBadge(text: post.status.label, color: post.status.color)
            }
          }
          .rowFont()
        }
      } header: {
        zh("被引用")
      }
      Section {
        Button(role: .destructive) {
          confirmingDelete = true
        } label: {
          zh("删除图片")
        }
        .rowFont()
      }
    }
    .formStyle(.grouped)
  }

  private func sizeText(_ image: AdminImage) -> String {
    guard let width = image.width, let height = image.height else { return "未知" }
    return "\(width) × \(height)"
  }

  private func copy(_ text: String, _ note: String) {
    Pasteboard.copy(text)
    copied = note
  }

  private func load() async {
    guard let client else { return }
    do {
      let value = try await client.image(id: imageId)
      folders = (try? await client.folders()) ?? []
      detail = value
      filename = value.image.filename
      description = value.image.description
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func save() async {
    guard let client else { return }
    saving = true
    defer { saving = false }
    do {
      _ = try await client.updateImage(id: imageId, ImageUpdateInput(filename: filename, description: description))
      session.dataChanged()
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func move(to folderId: Int?) async {
    guard let client else { return }
    do {
      try await client.moveImages(ids: [imageId], folderId: folderId)
      session.dataChanged()
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func delete() async {
    guard let client, let detail else { return }
    do {
      try await client.deleteImages(ids: [imageId], force: !detail.posts.isEmpty)
      session.dataChanged()
      dismiss()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}
