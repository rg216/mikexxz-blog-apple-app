import BlogKit
import SwiftUI

/// 译文的说明（网站的原则：内容准确优先于翻译完整，读者要知道自己看的是什么）：
/// - 请求的语言没有译文：显示的是原文
/// - 机器翻译：标出来，并给出原文
/// - 原文在翻译之后改过：译文可能过时
struct TranslationNotice: View {
  let post: PublicPost
  let requestedLocale: ContentLocale
  let switchLocale: (ContentLocale) -> Void

  @Environment(\.locale) private var locale

  var body: some View {
    if post.locale != requestedLocale {
      callout(systemImage: "globe") {
        Text("This post isn't available in \(requestedLocale.name(in: locale)) yet. Showing the original in \(post.locale.name(in: locale)).")
      }
    } else if let translation = post.translation {
      if translation.outdated {
        callout(systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
          Text("The original has been updated since this translation was made.")
        } action: {
          readOriginal
        }
      } else if translation.origin == .machine {
        callout(systemImage: "sparkles") {
          Text("This post was machine-translated from \(post.sourceLocale.name(in: locale)).")
        } action: {
          readOriginal
        }
      }
    }
  }

  private var readOriginal: some View {
    Button("Read the Original") { switchLocale(post.sourceLocale) }
      .font(.app(.subheadline).weight(.semibold))
  }

  private func callout(systemImage: String, @ViewBuilder text: () -> Text, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        text()
          .font(.app(.subheadline))
        action()
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(.fill.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
  }
}
