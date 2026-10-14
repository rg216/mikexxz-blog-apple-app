import BlogKit
import SwiftUI

/// 归档：当前语言的全部文章，按月分组（站点时区）
struct ArchiveView: View {
  @Environment(\.blogClient) private var client
  @Environment(ReaderSettings.self) private var settings
  @Environment(\.locale) private var locale
  @State private var state: Loadable<[ArchiveMonth]> = .loading

  var body: some View {
    content
      .navigationTitle("Archive")
      .task(id: settings.contentLocale) { await load() }
  }

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      ErrorStateView(error: error) { await load() }
    case .loaded(let months) where months.isEmpty:
      ContentUnavailableView("No Posts", systemImage: "archivebox")
    case .loaded(let months):
      List {
        ForEach(months) { month in
          Section {
            ForEach(month.items) { item in
              NavigationLink(value: Route.post(slug: item.slug)) {
                LabeledContent {
                  Text(item.publishedAt, format: SiteCalendar.dayStyle(locale: locale))
                    .monospacedDigit()
                } label: {
                  Text(item.title)
                    .typesettingLanguage(item.locale.language)
                }
              }
              .rowFont()
            }
          } header: {
            Text(month.month.firstDay, format: SiteCalendar.monthStyle(locale: locale))
          }
        }
      }
      .refreshable { await load() }
    }
  }

  private func load() async {
    do {
      state = .loaded(Archive.group(try await client.archive(locale: settings.contentLocale)))
    } catch .cancelled {
      return
    } catch {
      if state.value == nil { state = .failed(error) }
    }
  }
}
