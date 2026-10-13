import Foundation

/// 博客公开接口的客户端（只读）。
///
/// 直接请求 API 项目，不经过网站的 `/api` 代理：网站走代理是为了让浏览器里的 session cookie
/// 是第一方的、Passkey 在前端源下完成；App 不用 cookie，多绕一跳只会更慢。
/// 限流按 `X-Forwarded-For` 的第一项算，直连时就是读者自己的 IP，和浏览器一样各算各的。
public struct BlogClient: Sendable {
  public static let productionURL = URL(string: "https://mikexzx-blog-api.vercel.app")!

  public let baseURL: URL
  private let session: URLSession

  public init(baseURL: URL = productionURL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  // MARK: - 接口

  public func posts(locale: ContentLocale, filter: PostFilter = PostFilter(), cursor: String? = nil, limit: Int = 20) async throws(BlogAPIError) -> Page<PostSummary> {
    var query = [URLQueryItem(name: "locale", value: locale.rawValue), URLQueryItem(name: "limit", value: String(limit))]
    if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
    return try await get(["posts"], query: query + filter.queryItems)
  }

  public func post(slug: String, locale: ContentLocale) async throws(BlogAPIError) -> PublicPost {
    try await get(["posts", slug], query: [URLQueryItem(name: "locale", value: locale.rawValue)])
  }

  public func tags(locale: ContentLocale) async throws(BlogAPIError) -> [TagWithCount] {
    try await get(["tags"], query: [URLQueryItem(name: "locale", value: locale.rawValue)])
  }

  public func archive(locale: ContentLocale) async throws(BlogAPIError) -> [ArchiveItem] {
    try await get(["archive"], query: [URLQueryItem(name: "locale", value: locale.rawValue)])
  }

  /// 按相关度取前 20 条，不分页
  public func search(_ text: String, locale: ContentLocale, filter: PostFilter = PostFilter()) async throws(BlogAPIError) -> [SearchHit] {
    let query = [URLQueryItem(name: "q", value: String(text.prefix(SearchLimits.queryMaxLength))), URLQueryItem(name: "locale", value: locale.rawValue)]
    let result: SearchResult = try await get(["search"], query: query + filter.queryItems)
    return result.items
  }

  /// 只读取阅读数，不计数：计数接口是写请求，API 要求 `Origin` 等于网站的源（防 CSRF），
  /// App 发不出合法的 Origin。要计入 App 的阅读，得在 API 那边为这个不带 cookie 的接口放开 Origin 检查。
  public func views(slug: String) async throws(BlogAPIError) -> Int? {
    let count: ViewCount = try await get(["posts", slug, "views"], query: [], useCacheWhenOffline: false)
    return count.views
  }

  /// 未登录时只有已显示的评论；接口带 `no-store`，离线时没有缓存可用
  public func comments(slug: String) async throws(BlogAPIError) -> CommentList {
    try await get(["posts", slug, "comments"], query: [], useCacheWhenOffline: false)
  }

  // MARK: - 请求

  func request(_ path: [String], query: [URLQueryItem]) -> URLRequest {
    var url = baseURL
    for component in path { url.append(component: component) }
    if !query.isEmpty { url.append(queryItems: query) }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  /// 离线时退回 URLCache 里的旧响应：API 的列表和文章是 `max-age=0, must-revalidate`，
  /// URLCache 照样存下来，只是平时每次都去服务器确认。断网时读旧的总比一片空白好。
  private func get<T: Decodable>(_ path: [String], query: [URLQueryItem], useCacheWhenOffline: Bool = true) async throws(BlogAPIError) -> T {
    let request = request(path, query: query)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.isConnectivityProblem {
      guard useCacheWhenOffline, let cached = try? await cachedResponse(for: request) else { throw .offline }
      (data, response) = cached
    } catch let error as URLError where error.code == .cancelled {
      throw .cancelled
    } catch is CancellationError {
      throw .cancelled
    } catch {
      throw .transport(String(describing: error))
    }
    return try Self.decode(data: data, response: response)
  }

  private func cachedResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
    var cacheOnly = request
    cacheOnly.cachePolicy = .returnCacheDataDontLoad
    return try await session.data(for: cacheOnly)
  }

  static func decode<T: Decodable>(data: Data, response: URLResponse) throws(BlogAPIError) -> T {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      // 错误体是 { error: { code, message } }；message 是给后台看的中文，App 只按 code 显示本地化文案
      if let body = try? decoder.decode(APIErrorBody.self, from: data) {
        throw .server(status: status, code: APIErrorCode(rawValue: body.error.code))
      }
      throw .server(status: status, code: nil)
    }
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      throw .decoding(String(describing: error))
    }
  }

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let string = try decoder.singleValueContainer().decode(String.self)
      if let date = (try? Date(string, strategy: withFractionalSeconds)) ?? (try? Date(string, strategy: .iso8601)) {
        return date
      }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "不是 ISO 8601 时间：\(string)"))
    }
    return decoder
  }()

  /// JS 的 toISOString() 带毫秒（2026-10-09T02:00:00.000Z），默认的 .iso8601 不认毫秒
  private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

private struct APIErrorBody: Decodable {
  struct Detail: Decodable {
    let code: String
    let message: String
  }

  let error: Detail
}

extension URLError {
  /// 没有网络、连不上服务器：这时可以退回缓存
  var isConnectivityProblem: Bool {
    switch code {
    case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
      .timedOut, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
      true
    default:
      false
    }
  }
}
