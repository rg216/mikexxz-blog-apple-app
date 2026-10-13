import Foundation

/// 网站上的地址：分享用的网页地址，以及把正文里指向本站的链接识别成 App 内的页面。
public enum SiteLinks {
  /// 与网站的 `SITE_URL` 默认值一致；以后换了自己的域名在这里改
  public static let siteURL = URL(string: "https://mikexzx-blog.vercel.app")!

  /// 文章的网页地址：中文不加前缀，其他语言 /en/posts/<slug>
  public static func postURL(slug: String, locale: ContentLocale) -> URL {
    url(path: ["posts", slug], locale: locale)
  }

  public static func tagURL(slug: String, locale: ContentLocale) -> URL {
    url(path: ["tags", slug], locale: locale)
  }

  private static func url(path: [String], locale: ContentLocale) -> URL {
    var url = siteURL
    if locale != .default { url.append(component: locale.rawValue) }
    for component in path { url.append(component: component) }
    return url
  }

  /// 指向本站文章或标签页的链接（含相对地址 /posts/…）；其他链接返回 nil，交给系统打开。
  /// 网址里的语言前缀不决定打开哪种语言：结构校验要求译文保留原文的链接，英文译文里的站内链接
  /// 也是不带前缀的中文网址；App 里按读者选的语言打开才对。
  public static func route(for url: URL) -> SiteRoute? {
    if let host = url.host() {
      guard host.lowercased() == siteURL.host(), url.scheme == "https" || url.scheme == "http" else { return nil }
    } else if url.scheme != nil {
      return nil
    }
    var components = url.path(percentEncoded: false).split(separator: "/").map(String.init)
    if let first = components.first, ContentLocale.supported.contains(where: { $0.rawValue == first }) {
      components.removeFirst()
    }
    guard components.count == 2 else { return nil }
    let slug = components[1]
    guard isSlug(slug) else { return nil }
    switch components[0] {
    case "posts": return .post(slug: slug)
    case "tags": return .tag(slug: slug)
    default: return nil
    }
  }

  /// 网站的 slugSchema：小写字母、数字、单个连字符分隔
  static func isSlug(_ value: String) -> Bool {
    value.wholeMatch(of: /[a-z0-9]+(?:-[a-z0-9]+)*/) != nil && value.count <= 200
  }
}

public enum SiteRoute: Hashable, Sendable {
  case post(slug: String)
  case tag(slug: String)
}
