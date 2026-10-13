import BlogKit
import Foundation
import Observation

/// 读者的偏好：文章用哪种语言显示。
///
/// 界面语言跟随系统（iOS 设置里可以单独给这个 App 选语言），文章语言单独选：
/// 网站不按 Accept-Language 自动跳转（会干扰搜索引擎），App 没有这个顾虑，
/// 所以第一次打开时按界面语言选，之后以读者的选择为准。
@Observable
final class ReaderSettings {
  private static let contentLocaleKey = "contentLocale"

  var contentLocale: ContentLocale {
    didSet { defaults.set(contentLocale.rawValue, forKey: Self.contentLocaleKey) }
  }

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let saved = defaults.string(forKey: Self.contentLocaleKey).map(ContentLocale.init(rawValue:)),
      ContentLocale.supported.contains(saved)
    {
      contentLocale = saved
    } else {
      contentLocale = ContentLocale.preferred(from: Bundle.main.preferredLocalizations + Locale.preferredLanguages)
    }
  }
}
