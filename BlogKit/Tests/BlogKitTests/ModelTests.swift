import Foundation
import Testing

@testable import BlogKit

/// 用线上 API 真实返回的 JSON（截短）检查解码
struct DecodingTests {
  func decode<T: Decodable>(_ type: T.Type, _ json: String, status: Int = 200) throws(BlogAPIError) -> T {
    let response = HTTPURLResponse(url: URL(string: "https://api.example")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    return try BlogClient.decode(data: Data(json.utf8), response: response)
  }

  @Test func postPage() throws {
    let page = try decode(
      Page<PostSummary>.self,
      #"""
      {"items":[{"slug":"why-build-a-blog-from-scratch","title":"为什么要从零写一个博客","excerpt":"现成的…","status":"published","publishedAt":"2026-10-09T02:00:00.000Z","tags":[{"slug":"meta","name":"关于本站","locale":"zh"}],"cover":{"url":"https://pub.r2.dev/images/2026/10/Aa9j6W3BKvL_m-Vm.png","alt":"logo","width":180,"height":180,"variants":[]},"locale":"zh","someFutureField":1}],"nextCursor":"eyJwIjoi"}
      """#)
    #expect(page.items.count == 1)
    #expect(page.nextCursor == "eyJwIjoi")
    let post = page.items[0]
    #expect(post.publishedAt == Date(timeIntervalSince1970: 1_791_511_200))
    #expect(post.cover?.meta == ImageMeta(width: 180, height: 180, variants: []))
    #expect(post.tags.first?.locale == .zh)
  }

  @Test func publicPostWithTranslation() throws {
    let post = try decode(
      PublicPost.self,
      #"""
      {"slug":"a","title":"A","excerpt":"","status":"published","publishedAt":"2026-10-09T02:00:00Z","tags":[],"cover":null,"locale":"en","contentMd":"x","sourceLocale":"zh","availableLocales":["zh","en","ja"],"images":{"images/2026/10/K9DF09pTHI9YMZhp.jpg":{"width":750,"height":750,"variants":[640]}},"translation":{"origin":"machine","translatedAt":"2026-10-11T13:09:15.299Z","outdated":false}}
      """#)
    #expect(post.translation?.origin == .machine)
    #expect(post.availableLocales == ContentLocale.supported)
    #expect(post.images["images/2026/10/K9DF09pTHI9YMZhp.jpg"]?.variants == [640])
  }

  @Test func unknownLocalesStillDecode() throws {
    let tags = try decode([TagWithCount].self, #"[{"slug":"a","name":"가","locale":"ko","count":1}]"#)
    #expect(tags[0].locale.rawValue == "ko")
    #expect(!ContentLocale.supported.contains(tags[0].locale))
  }

  @Test func commentThreadsFlattenTheTopLevelComment() throws {
    let list = try decode(
      CommentList.self,
      #"""
      {"threads":[{"id":1,"author":{"login":"octo","name":null,"avatarUrl":"https://avatars.example/1"},"bodyMd":"hi","createdAt":"2026-10-10T00:00:00.000Z","editedAt":null,"deleted":false,"mine":false,"replyTo":null,"status":"approved","replies":[{"id":2,"author":null,"bodyMd":"","createdAt":"2026-10-10T01:00:00.000Z","editedAt":null,"deleted":true,"mine":false,"replyTo":{"login":"octo"},"status":"approved"}]}],"count":1}
      """#)
    #expect(list.threads[0].comment.author?.displayName == "octo")
    #expect(list.threads[0].replies[0].replyTo?.login == "octo")
  }

  @Test func errorBodiesBecomeCodes() {
    #expect(throws: BlogAPIError.server(status: 404, code: .notFound)) {
      try decode(PublicPost.self, #"{"error":{"code":"not_found","message":"文章不存在"}}"#, status: 404)
    }
    #expect(throws: BlogAPIError.server(status: 502, code: nil)) {
      try decode(PublicPost.self, "<html>Bad gateway</html>", status: 502)
    }
  }
}

struct ContentLocaleTests {
  @Test func preferredLanguage() {
    #expect(ContentLocale.preferred(from: ["ja-JP", "en-US"]) == .ja)
    #expect(ContentLocale.preferred(from: ["fr-FR", "en-GB"]) == .en)
    #expect(ContentLocale.preferred(from: ["zh-Hant-TW"]) == .zh)
    #expect(ContentLocale.preferred(from: ["de"]) == .zh)
  }
}

struct HighlightTests {
  @Test func utf16RangesMapOntoCharacters() {
    // 😀 占两个 UTF-16 码元：JS 下标 2..<4 是"博客"
    let text = HighlightedText(text: "😀博客 blog", highlights: [HighlightRange(start: 2, end: 4), HighlightRange(start: 5, end: 9)])
    let attributed = text.attributed(highlight: AttributeContainer().inlinePresentationIntent(.stronglyEmphasized))
    let marked = attributed.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(attributed[$0.range].characters) }
    #expect(marked == ["博客", "blog"])
  }

  @Test func invalidRangesAreIgnored() {
    // 1..<2 切开了 😀 的代理对；10 越界
    let text = HighlightedText(text: "😀a", highlights: [HighlightRange(start: 1, end: 2), HighlightRange(start: 2, end: 10)])
    let attributed = text.attributed(highlight: AttributeContainer().inlinePresentationIntent(.stronglyEmphasized))
    #expect(attributed.runs.allSatisfy { $0.inlinePresentationIntent == nil })
  }
}

struct SiteTests {
  @Test func postURLs() {
    #expect(SiteLinks.postURL(slug: "a-b", locale: .zh).absoluteString == "https://mikexzx-blog.vercel.app/posts/a-b")
    #expect(SiteLinks.postURL(slug: "a-b", locale: .ja).absoluteString == "https://mikexzx-blog.vercel.app/ja/posts/a-b")
  }

  @Test func routes() {
    #expect(SiteLinks.route(for: URL(string: "https://mikexzx-blog.vercel.app/en/posts/hello")!) == .post(slug: "hello"))
    #expect(SiteLinks.route(for: URL(string: "https://mikexzx-blog.vercel.app/tags/swift")!) == .tag(slug: "swift"))
    #expect(SiteLinks.route(for: URL(string: "https://mikexzx-blog.vercel.app/archive")!) == nil)
    #expect(SiteLinks.route(for: URL(string: "https://example.com/posts/hello")!) == nil)
    #expect(SiteLinks.route(for: URL(string: "https://mikexzx-blog.vercel.app/posts/Bad_Slug")!) == nil)
  }

  @Test func archiveGroupsBySiteTimeZone() throws {
    // 2026-09-30T16:30Z 是北京时间 10 月 1 日
    let items = try JSONDecoder.blog.decode(
      [ArchiveItem].self,
      from: Data(
        #"""
        [{"slug":"c","title":"C","publishedAt":"2026-10-05T00:00:00.000Z","locale":"zh"},
         {"slug":"b","title":"B","publishedAt":"2026-09-30T16:30:00.000Z","locale":"zh"},
         {"slug":"a","title":"A","publishedAt":"2026-09-30T15:30:00.000Z","locale":"zh"}]
        """#.utf8))
    let months = Archive.group(items)
    #expect(months.map(\.month.description) == ["2026-10", "2026-09"])
    #expect(months[0].items.map(\.slug) == ["c", "b"])
  }

  @Test func yearMonthParsing() {
    #expect(YearMonth("2026-10") == YearMonth(year: 2026, month: 10))
    #expect(YearMonth("2026-13") == nil)
    #expect(YearMonth("26-10") == nil)
  }
}

extension JSONDecoder {
  static var blog: JSONDecoder { BlogClient.decoder }
}
