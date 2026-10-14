import BlogKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 媒体库：所有上传过的图片，可以被多篇文章引用。一层文件夹、搜索、只看没被引用的
struct MediaLibraryView: View {
  var body: some View {
    MediaGrid(mode: .browse)
      .navigationTitle(zh("媒体库"))
  }
}

/// 选图（头图、插入正文）：同一个网格，点一下就选中并关闭
struct MediaPickerView: View {
  let onPick: (AdminImage) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      MediaGrid(mode: .pick { image in
        onPick(image)
        dismiss()
      })
      .navigationTitle(zh("选择图片"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { zh("取消") }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 640, minHeight: 560)
    #endif
  }
}

private struct MediaGrid: View {
  enum Mode {
    case browse
    case pick((AdminImage) -> Void)
  }

  let mode: Mode

  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var images: [AdminImage]?
  @State private var folders: [MediaFolder] = []
  @State private var folder = AdminClient.FolderFilter.all
  @State private var query = ""
  @State private var unusedOnly = false
  @State private var error: AdminAPIError?
  @State private var uploader = MediaUploader()
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var pickingPhotos = false
  @State private var importingFiles = false
  @State private var creatingFolder = false
  @State private var newFolderName = ""

  private struct Filter: Hashable {
    let folder: AdminClient.FolderFilter
    let query: String
    let unused: Bool
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let error {
          AdminErrorBanner(error: error) { Task { await load() } }
        }
        if uploader.isUploading {
          ProgressView(value: Double(uploader.done), total: Double(max(uploader.total, 1))) {
            zh("正在上传 \(uploader.done + 1) / \(uploader.total)")
          }
        }
        ForEach(uploader.failures, id: \.self) { failure in
          Label { zh(failure) } icon: { Image(systemName: "xmark.octagon.fill").foregroundStyle(.red) }
            .font(.footnote)
        }
        if let images {
          if images.isEmpty {
            zh(query.isEmpty && !unusedOnly ? "还没有图片。" : "没有符合条件的图片。")
              .foregroundStyle(.secondary)
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(images) { image in
              cell(image)
            }
          }
        } else if error == nil {
          ProgressView().frame(maxWidth: .infinity)
        }
      }
      .padding()
    }
    .searchable(text: $query, prompt: Text(verbatim: "文件名或描述"))
    .toolbar { toolbar }
    .task(id: Filter(folder: folder, query: query, unused: unusedOnly)) {
      // 输入搜索词时稍等一下再请求
      if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
      await load()
    }
    .onChange(of: session.revision) { Task { await load() } }
    .onChange(of: photoItems) { _, items in
      guard !items.isEmpty else { return }
      Task { await uploadPhotos(items) }
    }
    .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, matching: .images, photoLibrary: .shared())
    .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
      if case .success(let urls) = result { Task { await uploadFiles(urls) } }
    }
    .alert(Text(verbatim: "新建文件夹"), isPresented: $creatingFolder) {
      TextField(text: $newFolderName) { zh("名称") }
      Button { Task { await createFolder() } } label: { zh("创建") }
      Button(role: .cancel) {} label: { zh("取消") }
    }
  }

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Menu {
        // 菜单里放普通按钮，选择器由页面上的 .photosPicker 弹出：PhotosPicker 本身放进 Menu 的话，
        // 菜单一收起它就跟着消失，选择器弹不出来
        Button {
          pickingPhotos = true
        } label: {
          Label { zh("从照片上传") } icon: { Image(systemName: "photo.on.rectangle") }
        }
        Button {
          importingFiles = true
        } label: {
          Label { zh("从文件上传") } icon: { Image(systemName: "folder") }
        }
      } label: {
        Label { zh("上传") } icon: { Image(systemName: "plus") }
      }
      .disabled(uploader.isUploading)
    }
    ToolbarItem(placement: .secondaryAction) {
      Menu {
        Picker(selection: $folder) {
          zh("全部图片").tag(AdminClient.FolderFilter.all)
          zh("未归入文件夹").tag(AdminClient.FolderFilter.none)
          ForEach(folders) { folder in
            zh("\(folder.name)（\(folder.imageCount)）").tag(AdminClient.FolderFilter.folder(folder.id))
          }
        } label: {
          zh("文件夹")
        }
        Toggle(isOn: $unusedOnly) { zh("只看没被引用的") }
        Divider()
        Button {
          newFolderName = ""
          creatingFolder = true
        } label: {
          Label { zh("新建文件夹") } icon: { Image(systemName: "folder.badge.plus") }
        }
      } label: {
        Label { zh("筛选") } icon: { Image(systemName: "line.3.horizontal.decrease") }
      }
    }
  }

  @ViewBuilder private func cell(_ image: AdminImage) -> some View {
    let thumbnail = RemoteImage(url: image.url, meta: image.meta, contentMode: .fill)
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 8, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        if image.usage == 0 {
          zh("未引用")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(4)
        }
      }
      .accessibilityLabel(Text(verbatim: image.description.isEmpty ? image.filename : image.description))
    switch mode {
    case .browse:
      NavigationLink(value: AdminRoute.image(id: image.id)) { thumbnail }
        .buttonStyle(.plain)
    case .pick(let onPick):
      Button { onPick(image) } label: { thumbnail }
        .buttonStyle(.plain)
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      // 依次请求（async let 会丢掉 typed throws 的错误类型）；两个都很快
      images = try await client.images(folder: folder, search: query, unusedOnly: unusedOnly)
      folders = try await client.folders()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private var uploadFolderId: Int? {
    if case .folder(let id) = folder { id } else { nil }
  }

  private func uploadPhotos(_ items: [PhotosPickerItem]) async {
    guard let client else { return }
    var loaded: [MediaUploader.Item] = []
    for (index, item) in items.enumerated() {
      if let data = try? await item.loadTransferable(type: Data.self) {
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        loaded.append(MediaUploader.Item(data: data, filename: "photo-\(index + 1).\(ext)"))
      }
    }
    photoItems = []
    _ = await uploader.upload(loaded, folderId: uploadFolderId, client: client)
    await load()
  }

  private func uploadFiles(_ urls: [URL]) async {
    guard let client else { return }
    let loaded = urls.compactMap { url -> MediaUploader.Item? in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      return (try? Data(contentsOf: url)).map { MediaUploader.Item(data: $0, filename: url.lastPathComponent) }
    }
    _ = await uploader.upload(loaded, folderId: uploadFolderId, client: client)
    await load()
  }

  private func createFolder() async {
    guard let client else { return }
    let name = newFolderName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    do {
      let created = try await client.createFolder(name: name)
      folder = .folder(created.id)
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}
