import BlogKit
import Foundation

extension ContentLocale {
  /// 句子里提到的语言名用界面语言（"Chinese" / "中文" / "中国語"）；菜单里的选项才用自称
  func name(in locale: Locale) -> String {
    locale.localizedString(forLanguageCode: rawValue) ?? endonym
  }
}
