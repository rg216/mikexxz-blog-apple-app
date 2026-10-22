import Foundation

/// 后台接口的错误。后台和网页一样固定中文：服务器的 message 就是写给管理员看的，直接显示
public struct AdminAPIError: Error, Hashable, Sendable {
  public struct Issue: Codable, Hashable, Sendable {
    /// 字段路径，如 "slug"、"translations.en"
    public let path: String
    public let message: String
  }

  public enum Kind: Hashable, Sendable {
    case server, offline, decoding, transport, cancelled
  }

  public let kind: Kind
  /// HTTP 状态码；请求没发出去时为 0
  public let status: Int
  public let code: String?
  public let message: String
  public let issues: [Issue]

  public init(kind: Kind, status: Int = 0, code: String? = nil, message: String, issues: [Issue] = []) {
    self.kind = kind
    self.status = status
    self.code = code
    self.message = message
    self.issues = issues
  }

  /// session 失效（过期、在别处退出了）：要重新登录
  public var isUnauthorized: Bool { status == 401 }
  public var isNotFound: Bool { status == 404 }
  public var isConflict: Bool { status == 409 }

  /// 某个字段的错误（表单把它放在那一栏下面）
  public func issue(for path: String) -> String? {
    issues.first { $0.path == path }?.message
  }

  static let cancelled = AdminAPIError(kind: .cancelled, message: "已取消")
}

/// 后台接口的客户端：每个请求带 `Authorization: Bearer <token>`，不带 cookie。
///
/// 用单独的 URLSession，关掉 cookie：API 判断"不带 cookie 的 Bearer 请求"才免去 Origin 检查
/// （带 cookie 的请求可能来自浏览器，照常防 CSRF），所以 App 绝不能顺手带上什么 cookie。
/// 也不用 URLCache：后台的数据要最新的，离线时显示旧数据反而会误导。
public struct AdminClient: Sendable {
  public let baseURL: URL
  public let token: String
  private let session: URLSession

  public init(baseURL: URL, token: String, session: URLSession = AdminClient.makeSession()) {
    self.baseURL = baseURL
    self.token = token
    self.session = session
  }

  public static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    // 正文一段的译文可能要生成好几分钟（中间有心跳，见 TranslationStreamEvent.ping）
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 600
    return URLSession(configuration: configuration)
  }

  // MARK: - 登录

  /// 用授权码 + PKCE verifier 换 token（还没有 token，所以是静态方法）
  public static func exchange(baseURL: URL, code: String, verifier: String, session: URLSession = makeSession()) async throws(AdminAPIError) -> AppToken {
    struct Body: Encodable {
      let code: String
      let codeVerifier: String
    }
    let request = try makeRequest(baseURL: baseURL, token: nil, method: "POST", path: ["auth", "app", "token"], query: [], body: Body(code: code, codeVerifier: verifier))
    return try await decode(perform(request, session: session))
  }

  public func session() async throws(AdminAPIError) -> SessionInfo {
    try await get(["auth", "session"])
  }

  public func logout() async throws(AdminAPIError) {
    try await send("POST", ["auth", "logout"])
  }

  public func passkeys() async throws(AdminAPIError) -> [Passkey] {
    try await get(["auth", "passkeys"])
  }

  public func renamePasskey(id: String, name: String) async throws(AdminAPIError) -> Passkey {
    try await send("PATCH", ["auth", "passkeys", id], body: ["name": name])
  }

  public func deletePasskey(id: String) async throws(AdminAPIError) {
    try await send("DELETE", ["auth", "passkeys", id])
  }

  // MARK: - 文章

  /// 全部文章（含草稿），按更新时间倒序
  public func posts() async throws(AdminAPIError) -> [AdminPost] {
    try await get(["admin", "posts"])
  }

  public func post(id: Int) async throws(AdminAPIError) -> AdminPost {
    try await get(["admin", "posts", String(id)])
  }

  public func createPost(_ input: PostInput) async throws(AdminAPIError) -> AdminPost {
    try await send("POST", ["admin", "posts"], body: input)
  }

  public func updatePost(id: Int, _ input: PostInput) async throws(AdminAPIError) -> AdminPost {
    try await send("PATCH", ["admin", "posts", String(id)], body: input)
  }

  public func deletePost(id: Int) async throws(AdminAPIError) {
    try await send("DELETE", ["admin", "posts", String(id)])
  }

  // MARK: - 译文

  /// 还没有这种语言的译文时为 nil
  public func translation(postId: Int, locale: ContentLocale) async throws(AdminAPIError) -> AdminTranslation? {
    do {
      return try await get(["admin", "posts", String(postId), "translations", locale.rawValue])
    } catch where error.isNotFound && error.code == "not_found" {
      return nil
    }
  }

  public func saveTranslation(postId: Int, locale: ContentLocale, _ input: TranslationInput) async throws(AdminAPIError) -> AdminTranslation {
    try await send("PUT", ["admin", "posts", String(postId), "translations", locale.rawValue], body: input)
  }

  public func deleteTranslation(postId: Int, locale: ContentLocale) async throws(AdminAPIError) {
    try await send("DELETE", ["admin", "posts", String(postId), "translations", locale.rawValue])
  }

  public func translationConfig() async throws(AdminAPIError) -> TranslationConfig {
    try await get(["admin", "translation", "config"])
  }

  public func translationPlan(postId: Int) async throws(AdminAPIError) -> TranslationPlan {
    try await get(["admin", "posts", String(postId), "translation-plan"])
  }

  private struct GenerateBody: Encodable {
    let part: String
    let index: Int?
    let sourceHash: String
    let model: String
  }

  public func generateTitle(postId: Int, locale: ContentLocale, sourceHash: String, model: String) async throws(AdminAPIError) -> TranslationTitleResult {
    try await send(
      "POST", ["admin", "posts", String(postId), "translations", locale.rawValue, "generate"],
      body: GenerateBody(part: "title", index: nil, sourceHash: sourceHash, model: model))
  }

  /// 正文的第 index 段：NDJSON 流，逐行解码。服务器在开始流之前出的错（凭证、限流、409）照常抛出 AdminAPIError；
  /// 流开始后的错误是流里的 `.error` 事件。取消调用它的 Task 会断开连接，服务器随即中止上游请求、不再计费
  public func generateSegment(postId: Int, locale: ContentLocale, index: Int, sourceHash: String, model: String) async throws(AdminAPIError) -> AsyncThrowingStream<TranslationStreamEvent, any Error> {
    try await ndjson(
      ["admin", "posts", String(postId), "translations", locale.rawValue, "generate"], body: GenerateBody(part: "body", index: index, sourceHash: sourceHash, model: model))
  }

  // MARK: - 标签

  public func tags() async throws(AdminAPIError) -> [AdminTag] {
    try await get(["admin", "tags"])
  }

  public func createTag(_ input: TagInput) async throws(AdminAPIError) -> AdminTag {
    try await send("POST", ["admin", "tags"], body: input)
  }

  public func updateTag(id: Int, _ input: TagInput) async throws(AdminAPIError) -> AdminTag {
    try await send("PATCH", ["admin", "tags", String(id)], body: input)
  }

  public func deleteTag(id: Int) async throws(AdminAPIError) {
    try await send("DELETE", ["admin", "tags", String(id)])
  }

  /// 把 id 合并进 into：用到它的文章改用 into，然后删掉它
  public func mergeTag(id: Int, into: Int) async throws(AdminAPIError) -> AdminTag {
    try await send("POST", ["admin", "tags", String(id), "merge"], body: ["into": into])
  }

  /// 请大模型给出各语言的译名（只回给表单，保存后才生效）
  public func translateTag(name: String, slug: String) async throws(AdminAPIError) -> TagTranslateResult {
    try await send("POST", ["admin", "tags", "translate"], body: ["name": name, "slug": slug])
  }

  // MARK: - 评论

  public func comments(status: CommentStatus) async throws(AdminAPIError) -> [AdminComment] {
    try await get(["admin", "comments"], query: [URLQueryItem(name: "status", value: status.rawValue)])
  }

  public func pendingCommentCount() async throws(AdminAPIError) -> Int {
    struct Count: Decodable { let count: Int }
    let result: Count = try await get(["admin", "comments", "pending-count"])
    return result.count
  }

  public func moderateComment(id: Int, status: CommentStatus) async throws(AdminAPIError) {
    try await send("PATCH", ["admin", "comments", String(id)], body: ["status": status.rawValue])
  }

  public func deleteComment(id: Int) async throws(AdminAPIError) {
    try await send("DELETE", ["admin", "comments", String(id)])
  }

  public func commenters() async throws(AdminAPIError) -> [AdminCommenter] {
    try await get(["admin", "commenters"])
  }

  public func setCommenterTrust(id: Int, trust: CommenterTrust) async throws(AdminAPIError) -> AdminCommenter {
    try await send("PATCH", ["admin", "commenters", String(id)], body: ["trust": trust.rawValue])
  }

  /// 按 GitHub 用户名直接加入白名单
  public func addTrustedCommenter(login: String) async throws(AdminAPIError) -> AdminCommenter {
    try await send("POST", ["admin", "commenters"], body: ["login": login])
  }

  // MARK: - 媒体库

  public enum FolderFilter: Hashable, Sendable {
    case all, none
    case folder(Int)

    var queryValue: String {
      switch self {
      case .all: "all"
      case .none: "none"
      case .folder(let id): String(id)
      }
    }
  }

  public func images(folder: FolderFilter = .all, search: String = "", unusedOnly: Bool = false) async throws(AdminAPIError) -> [AdminImage] {
    var query = [URLQueryItem(name: "folder", value: folder.queryValue)]
    let trimmed = search.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty { query.append(URLQueryItem(name: "q", value: trimmed)) }
    if unusedOnly { query.append(URLQueryItem(name: "unused", value: "1")) }
    return try await get(["admin", "images"], query: query)
  }

  public func image(id: Int) async throws(AdminAPIError) -> AdminImageDetail {
    try await get(["admin", "images", String(id)])
  }

  public func requestUpload(_ input: ImageUploadRequest) async throws(AdminAPIError) -> ImageUpload {
    try await send("POST", ["admin", "images"], body: input)
  }

  /// 把文件直接 PUT 到对象存储（不经过 API）；预签名的头必须原样带上
  public func upload(_ data: Data, to target: PresignedPut) async throws(AdminAPIError) {
    var request = URLRequest(url: target.url)
    request.httpMethod = target.method
    for (name, value) in target.headers { request.setValue(value, forHTTPHeaderField: name) }
    let response: URLResponse
    do {
      (_, response) = try await session.upload(for: request, from: data)
    } catch {
      throw Self.transportError(error)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw AdminAPIError(kind: .server, status: status, message: "上传到图片存储失败（HTTP \(status)）")
    }
  }

  /// 文件都传完后确认：API 核对文件并读出宽高，图片才算可用
  public func confirmImage(id: Int) async throws(AdminAPIError) -> AdminImage {
    try await send("POST", ["admin", "images", String(id), "confirm"])
  }

  public func updateImage(id: Int, _ input: ImageUpdateInput) async throws(AdminAPIError) -> AdminImage {
    try await send("PATCH", ["admin", "images", String(id)], body: input)
  }

  /// 仍被文章引用的图片需要 force，否则 409（message 里列出受影响的文章）
  public func deleteImages(ids: [Int], force: Bool) async throws(AdminAPIError) {
    struct Body: Encodable {
      let ids: [Int]
      let force: Bool
    }
    struct Result: Decodable { let deleted: Int }
    let _: Result = try await send("POST", ["admin", "images", "delete"], body: Body(ids: ids, force: force))
  }

  public func moveImages(ids: [Int], folderId: Int?) async throws(AdminAPIError) {
    struct Body: Encodable {
      let ids: [Int]
      let folderId: Int?

      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ids, forKey: .ids)
        if let folderId { try container.encode(folderId, forKey: .folderId) } else { try container.encodeNil(forKey: .folderId) }
      }

      enum CodingKeys: String, CodingKey { case ids, folderId }
    }
    struct Result: Decodable { let moved: Int }
    let _: Result = try await send("POST", ["admin", "images", "move"], body: Body(ids: ids, folderId: folderId))
  }

  public func folders() async throws(AdminAPIError) -> [MediaFolder] {
    try await get(["admin", "media-folders"])
  }

  public func createFolder(name: String) async throws(AdminAPIError) -> MediaFolder {
    try await send("POST", ["admin", "media-folders"], body: ["name": name])
  }

  public func renameFolder(id: Int, name: String) async throws(AdminAPIError) {
    try await send("PATCH", ["admin", "media-folders", String(id)], body: ["name": name])
  }

  public func deleteFolder(id: Int) async throws(AdminAPIError) {
    try await send("DELETE", ["admin", "media-folders", String(id)])
  }

  // MARK: - 生成头图

  public func coverConfig() async throws(AdminAPIError) -> CoverConfig {
    try await get(["admin", "covers", "config"])
  }

  public func writeCoverBrief(_ input: CoverBriefInput) async throws(AdminAPIError) -> CoverBriefResult {
    try await send("POST", ["admin", "covers", "brief"], body: input)
  }

  private struct CoverImageBody: Encodable {
    let prompt: String
  }

  /// 出图：NDJSON 流（ping / partial … 以 done 或 error 结束）。模型、画质、风格都用服务器设置里的。
  /// 开始流之前的错误（内容审核拒绝提示词 400、限流 429、凭证 502）照常抛出；取消 Task 即断开、上游随之中止
  public func generateCoverImage(prompt: String) async throws(AdminAPIError) -> AsyncThrowingStream<CoverImageStreamEvent, any Error> {
    try await ndjson(["admin", "covers", "generate"], body: CoverImageBody(prompt: prompt))
  }

  // MARK: - 设置与状态

  public func settings() async throws(AdminAPIError) -> SiteSettings {
    try await get(["admin", "settings"])
  }

  public func updateSettings(_ changes: [String: String]) async throws(AdminAPIError) -> SiteSettings {
    try await send("PATCH", ["admin", "settings"], body: changes)
  }

  public func status() async throws(AdminAPIError) -> SystemStatus {
    try await get(["admin", "status"])
  }

  // MARK: - 请求

  /// POST 一个请求，响应是 NDJSON 流：逐行解码成事件。非 2xx 的响应（流开始之前的错误）读完整个响应体，照常抛出 AdminAPIError
  private func ndjson<Event: Decodable & Sendable>(_ path: [String], body: some Encodable) async throws(AdminAPIError) -> AsyncThrowingStream<Event, any Error> {
    let request = try Self.makeRequest(baseURL: baseURL, token: token, method: "POST", path: path, query: [], body: body, accept: "application/x-ndjson")
    let bytes: URLSession.AsyncBytes
    let response: URLResponse
    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch {
      throw Self.transportError(error)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      var data = Data()
      do {
        for try await byte in bytes { data.append(byte) }
      } catch {
        throw Self.transportError(error)
      }
      throw Self.serverError(status: status, data: data)
    }
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await line in bytes.lines where !line.isEmpty {
            continuation.yield(try BlogClient.decoder.decode(Event.self, from: Data(line.utf8)))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func get<T: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws(AdminAPIError) -> T {
    let request = try Self.makeRequest(baseURL: baseURL, token: token, method: "GET", path: path, query: query, body: nil as String?)
    return try Self.decode(await Self.perform(request, session: session))
  }

  private func send<T: Decodable>(_ method: String, _ path: [String], body: (some Encodable)? = nil as String?) async throws(AdminAPIError) -> T {
    let request = try Self.makeRequest(baseURL: baseURL, token: token, method: method, path: path, query: [], body: body)
    return try Self.decode(await Self.perform(request, session: session))
  }

  /// 没有响应体的写操作（204）
  private func send(_ method: String, _ path: [String], body: (some Encodable)? = nil as String?) async throws(AdminAPIError) {
    let request = try Self.makeRequest(baseURL: baseURL, token: token, method: method, path: path, query: [], body: body)
    _ = try await Self.perform(request, session: session)
  }

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static func makeRequest(baseURL: URL, token: String?, method: String, path: [String], query: [URLQueryItem], body: (some Encodable)?, accept: String = "application/json") throws(AdminAPIError) -> URLRequest {
    var url = baseURL
    for component in path { url.append(component: component) }
    if !query.isEmpty { url.append(queryItems: query) }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(accept, forHTTPHeaderField: "Accept")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      do {
        request.httpBody = try encoder.encode(body)
      } catch {
        throw AdminAPIError(kind: .decoding, message: "请求内容无法编码：\(error)")
      }
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  static func perform(_ request: URLRequest, session: URLSession) async throws(AdminAPIError) -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw transportError(error)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw serverError(status: status, data: data) }
    return data
  }

  static func decode<T: Decodable>(_ data: Data) throws(AdminAPIError) -> T {
    do {
      return try BlogClient.decoder.decode(T.self, from: data)
    } catch {
      throw AdminAPIError(kind: .decoding, message: "服务器返回的数据格式不对（App 可能需要更新）：\(error)")
    }
  }

  static func serverError(status: Int, data: Data) -> AdminAPIError {
    struct Body: Decodable {
      struct Detail: Decodable {
        let code: String
        let message: String
        let issues: [AdminAPIError.Issue]?
      }

      let error: Detail
    }
    if let body = try? BlogClient.decoder.decode(Body.self, from: data) {
      return AdminAPIError(kind: .server, status: status, code: body.error.code, message: body.error.message, issues: body.error.issues ?? [])
    }
    return AdminAPIError(kind: .server, status: status, message: "服务器出错了（HTTP \(status)）")
  }

  static func transportError(_ error: any Error) -> AdminAPIError {
    if error is CancellationError { return .cancelled }
    if let urlError = error as? URLError {
      if urlError.code == .cancelled { return .cancelled }
      if urlError.isConnectivityProblem { return AdminAPIError(kind: .offline, message: "连不上服务器，请检查网络后重试") }
    }
    return AdminAPIError(kind: .transport, message: "请求失败：\(error.localizedDescription)")
  }
}
