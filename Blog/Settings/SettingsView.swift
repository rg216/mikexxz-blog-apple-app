import BlogKit
import SwiftUI

/// macOS 的"设置"窗口
struct SettingsView: View {
  @Environment(ReaderSettings.self) private var settings

  var body: some View {
    @Bindable var settings = settings
    Form {
      Picker("Article Language", selection: $settings.contentLocale) {
        ForEach(ContentLocale.supported) { locale in
          Text(locale.endonym).tag(locale)
        }
      }
      .rowFont()
      Text("Posts without a translation in this language are hidden from lists. Opening one shows the original.")
        .font(.app(.footnote))
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }
}
