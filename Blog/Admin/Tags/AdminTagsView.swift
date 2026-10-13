import BlogKit
import SwiftUI

/// 标签管理：新建、改名（名称 / slug / 译名）、合并、删除。编辑文章时只能从这里已有的标签里选
struct AdminTagsView: View {
  @Environment(\.adminClient) private var client
  @Environment(AdminSession.self) private var session
  @State private var tags: [AdminTag]?
  @State private var error: AdminAPIError?
  @State private var editing: TagEditorTarget?
  @State private var deleting: AdminTag?

  var body: some View {
    content
      .navigationTitle(zh("标签"))
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            editing = .new
          } label: {
            Label { zh("新建标签") } icon: { Image(systemName: "plus") }
          }
          .disabled(tags == nil)
        }
      }
      .sheet(item: $editing) { target in
        TagEditorView(target: target, allTags: tags ?? []) { await load() }
      }
      .confirmationDialog(
        Text(verbatim: deleting.map { "删除标签“\($0.name)”？" } ?? ""),
        isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
        titleVisibility: .visible, presenting: deleting
      ) { tag in
        Button(role: .destructive) {
          Task { await delete(tag) }
        } label: {
          zh("删除")
        }
      } message: { tag in
        zh(tag.postCount > 0 ? "\(tag.postCount) 篇文章会去掉这个标签。想换成别的标签的话，用“合并”。" : "没有文章用到它。")
      }
      .task { await load() }
      .refreshable { await load() }
  }

  @ViewBuilder private var content: some View {
    if let tags {
      List {
        if let error {
          AdminErrorBanner(error: error)
        }
        if tags.isEmpty {
          zh("还没有标签。").foregroundStyle(.secondary)
        }
        ForEach(tags) { tag in
          Button {
            editing = .edit(tag)
          } label: {
            AdminTagRow(tag: tag)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("admin-tag-row")
          .swipeActions {
            Button(role: .destructive) {
              deleting = tag
            } label: {
              Label { zh("删除") } icon: { Image(systemName: "trash") }
            }
          }
          .contextMenu {
            Button {
              editing = .edit(tag)
            } label: {
              Label { zh("编辑") } icon: { Image(systemName: "pencil") }
            }
            Button(role: .destructive) {
              deleting = tag
            } label: {
              Label { zh("删除") } icon: { Image(systemName: "trash") }
            }
          }
        }
      }
    } else if let error {
      VStack {
        AdminErrorBanner(error: error) { Task { await load() } }.padding()
        Spacer()
      }
    } else {
      ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func load() async {
    guard let client else { return }
    do {
      tags = try await client.tags()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  private func delete(_ tag: AdminTag) async {
    guard let client else { return }
    do {
      try await client.deleteTag(id: tag.id)
      await load()
    } catch {
      session.handle(error)
      self.error = error
    }
  }
}

private struct AdminTagRow: View {
  let tag: AdminTag

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        zh(tag.name)
          .font(.headline)
        zh("#\(tag.slug)")
          .font(.subheadline.monospaced())
          .foregroundStyle(.secondary)
        if !tag.missingTranslations.isEmpty {
          Label {
            zh("缺\(tag.missingTranslations.map(\.adminName).joined(separator: "、"))名称")
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.orange)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        zh("\(tag.publishedCount) 篇")
          .monospacedDigit()
        if tag.postCount > tag.publishedCount {
          zh("另有 \(tag.postCount - tag.publishedCount) 篇草稿")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .font(.subheadline)
    }
    .padding(.vertical, 4)
    .contentShape(.rect)
  }
}

enum TagEditorTarget: Identifiable {
  case new
  case edit(AdminTag)

  var id: Int {
    switch self {
    case .new: 0
    case .edit(let tag): tag.id
    }
  }

  var tag: AdminTag? {
    if case .edit(let tag) = self { tag } else { nil }
  }
}
