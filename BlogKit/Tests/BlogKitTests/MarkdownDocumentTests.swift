import Foundation
import Testing

@testable import BlogKit

struct MarkdownDocumentTests {
  @Test func standaloneImageBecomesFigureWithSizeAndCaption() throws {
    let document = MarkdownDocument(parsing: "![猫](https://cdn.example/images/2026/10/K9DF09pTHI9YMZhp.jpg#small \"图注\")\n")
    guard case .figure(let image) = try #require(document.blocks.first) else {
      Issue.record("应为 figure：\(document.blocks)")
      return
    }
    #expect(image.url.absoluteString == "https://cdn.example/images/2026/10/K9DF09pTHI9YMZhp.jpg")
    #expect(image.alt == "猫")
    #expect(image.title == "图注")
    #expect(image.size == .preset(.small))
    #expect(image.key == "images/2026/10/K9DF09pTHI9YMZhp.jpg")
  }

  @Test func inlineImageIsALinkWithItsDescription() throws {
    let document = MarkdownDocument(parsing: "看 ![图](https://a.example/x.png) 这张")
    guard case .paragraph(let text) = try #require(document.blocks.first) else {
      Issue.record("应为段落")
      return
    }
    #expect(String(text.characters) == "看 图 这张")
    #expect(text.runs.contains { $0.link == URL(string: "https://a.example/x.png") })
  }

  @Test func inlineStylesUseFoundationIntents() throws {
    let document = MarkdownDocument(parsing: "**粗** *斜* `code` ~~删~~ [链接](https://a.example)")
    guard case .paragraph(let text) = try #require(document.blocks.first) else {
      Issue.record("应为段落")
      return
    }
    let intents = text.runs.compactMap(\.inlinePresentationIntent)
    #expect(intents.contains(.stronglyEmphasized))
    #expect(intents.contains(.emphasized))
    #expect(intents.contains(.code))
    #expect(intents.contains(.strikethrough))
    #expect(text.runs.contains { $0.link == URL(string: "https://a.example") })
  }

  @Test func bareURLsAreAutolinked() throws {
    let document = MarkdownDocument(parsing: "详见 https://a.example/c 。")
    guard case .paragraph(let text) = try #require(document.blocks.first) else {
      Issue.record("应为段落")
      return
    }
    #expect(text.runs.contains { $0.link == URL(string: "https://a.example/c") })
  }

  @Test func relativeLinksResolveAgainstTheSiteAndUnsafeOnesAreDropped() throws {
    let document = MarkdownDocument(parsing: "[站内](/posts/hello) [脚本](javascript:alert(1)) [锚点](#top)")
    guard case .paragraph(let text) = try #require(document.blocks.first) else {
      Issue.record("应为段落")
      return
    }
    let links = text.runs.compactMap(\.link)
    #expect(links == [URL(string: "https://mikexzx-blog.vercel.app/posts/hello")!])
  }

  @Test func blockStructure() {
    let source = """
      ## 标题

      > 引用

      1. 一
      2. 二
         - 嵌套

      - [x] 完成
      - [ ] 未完成

      | 左 | 中 | 右 |
      |:---|:--:|---:|
      | a | b | c |

      ```swift
      let a = 1
      ```

      ---
      """
    let blocks = MarkdownDocument(parsing: source).blocks
    #expect(blocks.count == 7)
    guard case .heading(2, let heading) = blocks[0] else { Issue.record("标题"); return }
    #expect(String(heading.characters) == "标题")
    guard case .quote(let quote) = blocks[1] else { Issue.record("引用"); return }
    #expect(quote.count == 1)
    guard case .list(let ordered) = blocks[2] else { Issue.record("有序列表"); return }
    #expect(ordered.ordered && ordered.start == 1 && ordered.items.count == 2)
    #expect(ordered.items[1].blocks.count == 2)
    guard case .list(let tasks) = blocks[3] else { Issue.record("任务列表"); return }
    #expect(tasks.items.map(\.checkbox) == [true, false])
    guard case .table(let table) = blocks[4] else { Issue.record("表格"); return }
    #expect(table.alignments == [.leading, .center, .trailing])
    #expect(table.header.map { String($0.characters) } == ["左", "中", "右"])
    #expect(table.rows.count == 1)
    #expect(blocks[5] == .code(language: "swift", code: "let a = 1"))
    #expect(blocks[6] == .thematicBreak)
  }

  @Test func commentsHaveNoHeadingsOrImages() {
    let blocks = MarkdownDocument(parsing: "# 大标题\n\n![追踪](https://t.example/p.gif)", style: .comment).blocks
    #expect(blocks.count == 2)
    guard case .paragraph(let heading) = blocks[0] else { Issue.record("标题应降为段落"); return }
    #expect(heading.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    guard case .paragraph(let image) = blocks[1] else { Issue.record("图片应为链接"); return }
    #expect(String(image.characters) == "追踪")
  }
}

struct ImageReferenceTests {
  @Test func sizeFragments() {
    #expect(ImageReference.parseSize("a.jpg#medium").1 == .preset(.medium))
    #expect(ImageReference.parseSize("a.jpg#w=320").1 == .width(320))
    #expect(ImageReference.parseSize("a.jpg#w=10").1 == nil)
    #expect(ImageReference.parseSize("a.jpg#w=10").0 == "a.jpg#w=10")
    #expect(ImageReference.parseSize("a.jpg").1 == nil)
  }

  @Test func keysIgnoreVariantSuffixes() {
    #expect(ImageReference.key(of: "https://x/images/2026/10/abcdefghijklmnop-640w.jpg") == "images/2026/10/abcdefghijklmnop.jpg")
    // 随机串本身以 "-640w" 结尾时不能误删
    #expect(ImageReference.key(of: "https://x/images/2026/10/abcdefghijk-640w.jpg") == "images/2026/10/abcdefghijk-640w.jpg")
    #expect(ImageReference.key(of: "https://elsewhere.example/cat.jpg") == nil)
  }

  @Test func picksTheNarrowestSufficientVariant() {
    let url = URL(string: "https://x/images/2026/10/abcdefghijklmnop.jpg")!
    let meta = ImageMeta(width: 2560, height: 1440, variants: [640, 1280, 1920])
    #expect(ImageReference.bestSource(url, meta: meta, pixelWidth: 600).lastPathComponent == "abcdefghijklmnop-640w.jpg")
    #expect(ImageReference.bestSource(url, meta: meta, pixelWidth: 1300).lastPathComponent == "abcdefghijklmnop-1920w.jpg")
    #expect(ImageReference.bestSource(url, meta: meta, pixelWidth: 2400) == url)
    #expect(ImageReference.bestSource(url, meta: nil, pixelWidth: 100) == url)
  }
}

/// 期望值都来自网站实际用的 micromark-extension-gfm-autolink-literal 的结果
struct LiteralAutolinkTests {
  func links(_ text: String) -> [String] {
    var openBrackets = 0
    return LiteralAutolinks.matches(in: text, openBrackets: &openBrackets).map(\.url)
  }

  @Test func protocolLinks() {
    #expect(links("see https://a.b/c.") == ["https://a.b/c"])
    #expect(links("(https://a.b/c_(d))") == ["https://a.b/c_(d)"])
    #expect(links("(https://a.b/c)") == ["https://a.b/c"])
    // 非 ASCII 标点不是结尾：网页上就是这个（坏掉的）链接
    #expect(links("详见“https://a.b/c”。") == ["https://a.b/c”。"])
    // 前面紧跟汉字也照样识别（只要求前一个字符不是 ASCII 字母）
    #expect(links("访问https://a.b") == ["https://a.b"])
    #expect(links("xhttps://a.b") == [])
    #expect(links("https://a.b&nbsp;") == ["https://a.b"])
    #expect(links("https://a_b.c_d.e") == [])
    #expect(links("https://") == [])
  }

  @Test func wwwLinks() {
    #expect(links("go to www.example.com/x!") == ["http://www.example.com/x"])
    // www 前面紧跟汉字不是链接
    #expect(links("访问www.example.com，然后") == [])
    // 分词器不认，第二遍的正则认：网页上真的是指向 http://www 的链接
    #expect(links("www.") == ["http://www"])
  }

  @Test func emailLinks() {
    #expect(links("mail me@a.example.") == ["mailto:me@a.example"])
    #expect(links("a@b") == [])
    #expect(links("me@a.example1") == [])
  }

  @Test func autolinksAcrossSplitTextNodes() throws {
    let document = MarkdownDocument(parsing: "see https://a.b/c_d_e here")
    guard case .paragraph(let text) = try #require(document.blocks.first) else {
      Issue.record("应为段落")
      return
    }
    #expect(text.runs.compactMap(\.link) == [URL(string: "https://a.b/c_d_e")!])
  }
}

/// 和网站逐条对照：Fixtures/autolinks.json 由 scripts/generate-autolink-fixtures.mjs 用网站的 remark-gfm 生成
struct AutolinkFixtureTests {
  struct Fixture: Decodable {
    struct Link: Decodable, Equatable, CustomStringConvertible {
      let text: String
      let url: String
      var description: String { "[\(text)](\(url))" }
    }

    let input: String
    let links: [Link]
  }

  static func links(in blocks: [MarkdownBlock]) -> [Fixture.Link] {
    blocks.flatMap { block -> [Fixture.Link] in
      switch block {
      case .paragraph(let text), .heading(_, let text): links(in: text)
      case .quote(let children): links(in: children)
      case .list(let list): list.items.flatMap { links(in: $0.blocks) }
      default: []
      }
    }
  }

  /// 相邻、指向同一地址的片段合成一个链接（链接里有强调时会被切成几段）
  static func links(in text: AttributedString) -> [Fixture.Link] {
    var result: [Fixture.Link] = []
    var previousURL: URL?
    for run in text.runs {
      defer { previousURL = run.link }
      guard let url = run.link else { continue }
      let piece = String(text[run.range].characters)
      if url == previousURL, let last = result.popLast() {
        result.append(Fixture.Link(text: last.text + piece, url: last.url))
      } else {
        result.append(Fixture.Link(text: piece, url: url.absoluteString))
      }
    }
    return result
  }

  /// 网站给的是 Markdown 里的原文（mdast 的 url），App 里是 URL：两边经过同一个 URL(string:) 再比较
  /// （主机名转 punycode、小写）。URL(string:) 不接受的地址（"http://a.com]x"，浏览器同样解析不了）App 里不做成链接
  static func expected(_ links: [Fixture.Link]) -> [Fixture.Link] {
    links.compactMap { link in URL(string: link.url).map { Fixture.Link(text: link.text, url: $0.absoluteString) } }
  }

  /// 已知不一致：`_https://a.b/c_(d)`。micromark 先把网址切成链接（网址里的 `_` 不再参与强调），
  /// cmark 没有挂 autolink 扩展，先把 `_…_` 当成强调，网址在第二个 `_` 处就断了。
  /// 要一致只能换掉解析器；这种写法（下划线强调紧贴着含下划线和括号的网址）很少见，接受
  static func isKnownDifference(_ input: String) -> Bool {
    input.hasPrefix("_https://a.b/c_(d)")
  }

  @Test func matchesTheWebsite() throws {
    let url = try #require(Bundle.module.url(forResource: "autolinks", withExtension: "json", subdirectory: "Fixtures"))
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    #expect(fixtures.count > 1000)
    var mismatches: [String] = []
    for fixture in fixtures where !Self.isKnownDifference(fixture.input) {
      let actual = Self.links(in: MarkdownDocument(parsing: fixture.input).blocks)
      let expected = Self.expected(fixture.links)
      if actual != expected { mismatches.append("\(fixture.input)\n  网站 \(expected)\n  App  \(actual)") }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) 条不一致：\n\(mismatches.prefix(40).joined(separator: "\n"))")
  }
}
