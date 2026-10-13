import BlogKit
import SwiftUI

struct PostFeedView: View {
  let filter: PostFilter

  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  @Environment(\.locale) private var locale
  @State private var model = PostFeedModel()

  private var key: PostFeedModel.Key {
    PostFeedModel.Key(locale: settings.contentLocale, filter: filter)
  }

  var body: some View {
    content
      .task(id: key) { await model.load(key, client: client) }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading where model.posts.isEmpty:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error) where model.posts.isEmpty:
      ErrorStateView(error: error) { await model.load(key, client: client) }
    default:
      if model.posts.isEmpty {
        ContentUnavailableView(
          "No Posts",
          systemImage: "doc.text",
          description: Text("There are no posts in \(settings.contentLocale.name(in: locale)) here yet.")
        )
      } else {
        list
      }
    }
  }

  private var list: some View {
    List {
      ForEach(model.posts) { post in
        NavigationLink(value: Route.post(slug: post.slug)) {
          PostRow(post: post)
        }
        .accessibilityIdentifier("post-row")
        .onAppear {
          if post.id == model.posts.last?.id {
            Task { await model.loadMore(client: client) }
          }
        }
      }
      if model.nextCursor != nil {
        footer
      }
    }
    #if os(macOS)
      .listStyle(.inset)
    #else
      .listStyle(.plain)
    #endif
    .refreshable { await model.load(key, client: client) }
  }

  @ViewBuilder private var footer: some View {
    HStack {
      Spacer()
      if model.loadMoreError != nil {
        Button("Couldn't load more posts. Try Again") {
          Task { await model.loadMore(client: client) }
        }
      } else {
        ProgressView()
      }
      Spacer()
    }
    .listRowSeparator(.hidden)
    .padding(.vertical, 8)
  }
}
