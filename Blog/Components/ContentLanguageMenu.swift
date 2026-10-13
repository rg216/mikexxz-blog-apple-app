import BlogKit
import SwiftUI

extension ContentLocale {
  /// 句子里提到的语言名用界面语言（"Chinese" / "中文" / "中国語"）；菜单里的选项才用自称
  func name(in locale: Locale) -> String {
    locale.localizedString(forLanguageCode: rawValue) ?? endonym
  }
}

/// 工具栏里切换文章语言的菜单（网站导航栏里的语言切换）。语言名用自称：无论界面是什么语言，读者都认得出自己的语言
struct ContentLanguageMenu: ToolbarContent {
  @Environment(ReaderSettings.self) private var settings

  var body: some ToolbarContent {
    @Bindable var settings = settings
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Picker("Article Language", selection: $settings.contentLocale) {
          ForEach(ContentLocale.supported) { locale in
            Text(locale.endonym).tag(locale)
          }
        }
        .pickerStyle(.inline)
      } label: {
        Label("Article Language", systemImage: "globe")
      }
      .help("Article Language")
    }
  }
}
