import Foundation
import Markdown

/// Markdown 解析成的块结构，由 App 渲染成 SwiftUI 视图。
///
/// 解析交给 swift-markdown（cmark-gfm：表格、删除线、任务列表、裸网址自动链接，和网站的 remark-gfm 是同一套语法），
/// 块到视图的映射自己写：网站上图片尺寸片段、单独成段的图片成为 figure 这些约定，现成的渲染库都不认识。
///
/// 行内内容转换成 AttributedString，只用 Foundation 自带的属性（inlinePresentationIntent、link），
/// SwiftUI 的 Text 原生认识它们：粗体、斜体、代码、删除线、可点的链接都不用再处理。
public struct MarkdownDocument: Hashable, Sendable {
  public let blocks: [MarkdownBlock]

  public init(blocks: [MarkdownBlock]) {
    self.blocks = blocks
  }

  public init(parsing source: String, style: MarkdownStyle = .article) {
    let document = Document(parsing: source)
    var converter = Converter(style: style)
    blocks = converter.blocks(document.children)
  }
}

public enum MarkdownStyle: Sendable {
  /// 文章：作者写的，全部语法
  case article
  /// 评论：和网站的评论白名单一致，不显示图片（追踪像素）和标题
  case comment
}

public enum MarkdownBlock: Hashable, Sendable {
  case paragraph(AttributedString)
  case heading(level: Int, text: AttributedString)
  /// 单独成段的图片：比正文宽，title 作图注
  case figure(ImageReference)
  case code(language: String?, code: String)
  case quote([MarkdownBlock])
  case list(MarkdownList)
  case table(MarkdownTable)
  case thematicBreak
  /// 原样的 HTML 块：App 不解释 HTML，按文字显示
  case html(String)
}

public struct MarkdownList: Hashable, Sendable {
  public let ordered: Bool
  public let start: Int
  public let items: [MarkdownListItem]
}

public struct MarkdownListItem: Hashable, Sendable {
  /// 任务列表的勾选状态；普通列表项为 nil
  public let checkbox: Bool?
  public let blocks: [MarkdownBlock]
}

public struct MarkdownTable: Hashable, Sendable {
  public enum Alignment: Hashable, Sendable {
    case leading, center, trailing
  }

  public let alignments: [Alignment]
  public let header: [AttributedString]
  public let rows: [[AttributedString]]
}

// MARK: - 转换

private struct Converter {
  let style: MarkdownStyle
  /// 当前段落里还没配对的 "["（见 LiteralAutolinks）；每个块开始时归零
  let brackets = BracketCounter()

  mutating func blocks(_ children: MarkupChildren) -> [MarkdownBlock] {
    children.compactMap { block($0) }
  }

  mutating func block(_ markup: any Markup) -> MarkdownBlock? {
    switch markup {
    case let paragraph as Paragraph:
      if let image = standaloneImage(paragraph) {
        guard style == .article else { return .paragraph(inline(image)) }
        if let reference = imageReference(image) { return .figure(reference) }
      }
      return .paragraph(inlineChildren(paragraph))
    case let heading as Heading:
      let text = inlineChildren(heading)
      guard style == .article else { return .paragraph(text.applying(.stronglyEmphasized)) }
      return .heading(level: heading.level, text: text)
    case let code as CodeBlock:
      let language = code.language?.trimmingCharacters(in: .whitespaces)
      return .code(language: language?.isEmpty == false ? language : nil, code: code.code.trimmingTrailingNewlines())
    case let quote as BlockQuote:
      return .quote(blocks(quote.children))
    case let list as OrderedList:
      return .list(MarkdownList(ordered: true, start: Int(list.startIndex), items: listItems(list.children)))
    case let list as UnorderedList:
      return .list(MarkdownList(ordered: false, start: 1, items: listItems(list.children)))
    case let table as Table:
      return .table(self.table(table))
    case is ThematicBreak:
      return .thematicBreak
    case let html as HTMLBlock:
      let raw = html.rawHTML.trimmingTrailingNewlines()
      return raw.isEmpty ? nil : .html(raw)
    default:
      // 指令块之类网站也不支持的语法：退回纯文本，至少内容不丢
      let text = markup.format().trimmingTrailingNewlines()
      return text.isEmpty ? nil : .paragraph(AttributedString(text))
    }
  }

  mutating func listItems(_ children: MarkupChildren) -> [MarkdownListItem] {
    children.compactMap { child in
      guard let item = child as? ListItem else { return nil }
      let checkbox: Bool? =
        switch item.checkbox {
        case .checked: true
        case .unchecked: false
        case nil: nil
        }
      return MarkdownListItem(checkbox: checkbox, blocks: blocks(item.children))
    }
  }

  func table(_ table: Table) -> MarkdownTable {
    let alignments: [MarkdownTable.Alignment] = table.columnAlignments.map {
      switch $0 {
      case .center: .center
      case .right: .trailing
      case .left, nil: .leading
      }
    }
    let header = table.head.cells.map { inlineChildren($0) }
    let rows = table.body.rows.map { row in Array(row.cells.map { inlineChildren($0) }) }
    return MarkdownTable(alignments: alignments, header: Array(header), rows: Array(rows))
  }

  /// 段落里除了空白和换行只有一张图片
  func standaloneImage(_ paragraph: Paragraph) -> Markdown.Image? {
    let meaningful = paragraph.children.filter { child in
      if child is SoftBreak || child is LineBreak { return false }
      if let text = child as? Markdown.Text { return !text.string.allSatisfy(\.isWhitespace) }
      return true
    }
    guard meaningful.count == 1 else { return nil }
    return meaningful.first as? Markdown.Image
  }

  func imageReference(_ image: Markdown.Image) -> ImageReference? {
    guard let source = image.source, let reference = ImageReference(source: source, alt: image.plainText, title: image.title) else { return nil }
    guard Self.isSafe(reference.url) else { return nil }
    return reference
  }

  // MARK: 行内

  func inlineChildren(_ container: any Markup) -> AttributedString {
    brackets.count = 0
    return children(container, intent: [], link: nil)
  }

  func inline(_ markup: any Markup, intent: InlinePresentationIntent = [], link: URL? = nil) -> AttributedString {
    switch markup {
    case let text as Markdown.Text:
      return plainText(text.string, intent: intent, link: link)
    case is SoftBreak:
      return styled(" ", intent: intent, link: link)
    case is LineBreak:
      return styled("\n", intent: intent, link: link)
    case let code as InlineCode:
      return styled(code.code, intent: intent.union(.code), link: link)
    case is Emphasis:
      return children(markup, intent: intent.union(.emphasized), link: link)
    case is Strong:
      return children(markup, intent: intent.union(.stronglyEmphasized), link: link)
    case is Strikethrough:
      return children(markup, intent: intent.union(.strikethrough), link: link)
    case let anchor as Markdown.Link:
      return children(markup, intent: intent, link: anchor.destination.flatMap(Self.resolve) ?? link)
    case let image as Markdown.Image:
      // 行内图片（和文字混在一段里）和评论里的图片：显示成指向图片的链接，文字是图片描述
      let reference = imageReference(image)
      let label = image.plainText.isEmpty ? (reference?.url.lastPathComponent ?? "") : image.plainText
      return styled(label, intent: intent, link: link ?? reference?.url)
    case let html as InlineHTML:
      // 只认换行；其他标签不解释，也不显示标签本身
      let tag = html.rawHTML.lowercased().replacingOccurrences(of: " ", with: "")
      return tag.hasPrefix("<br") ? styled("\n", intent: intent, link: link) : AttributedString()
    default:
      return children(markup, intent: intent, link: link)
    }
  }

  /// 相邻的文字节点先拼起来再找裸网址：cmark 会在 `_`、`[` 这类没成对的标记处把文字切成几个节点，
  /// 不拼的话 `https://a.b/c_d` 只有前半截是链接
  func children(_ markup: any Markup, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
    var result = AttributedString()
    var pendingText = ""
    for child in markup.children {
      if let text = child as? Markdown.Text {
        pendingText += text.string
        continue
      }
      if !pendingText.isEmpty {
        result += plainText(pendingText, intent: intent, link: link)
        pendingText = ""
      }
      result += inline(child, intent: intent, link: link)
    }
    if !pendingText.isEmpty { result += plainText(pendingText, intent: intent, link: link) }
    return result
  }

  /// 纯文字：已经在链接里的原样输出（链接文字里不再找链接，和 micromark 一致），否则识别裸网址
  func plainText(_ string: String, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
    guard link == nil else { return styled(string, intent: intent, link: link) }
    let matches = LiteralAutolinks.matches(in: string, openBrackets: &brackets.count)
    guard !matches.isEmpty else { return styled(string, intent: intent, link: nil) }
    let scalars = Array(string.unicodeScalars)
    var result = AttributedString()
    var cursor = 0
    for match in matches {
      result += styled(Self.string(scalars[cursor..<match.range.lowerBound]), intent: intent, link: nil)
      let text = Self.string(scalars[match.range])
      let url = URL(string: match.url).flatMap { Self.isSafe($0) ? $0 : nil }
      result += styled(text, intent: intent, link: url)
      cursor = match.range.upperBound
    }
    result += styled(Self.string(scalars[cursor...]), intent: intent, link: nil)
    return result
  }

  static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
    var result = ""
    result.unicodeScalars.append(contentsOf: scalars)
    return result
  }

  func styled(_ string: String, intent: InlinePresentationIntent, link: URL?) -> AttributedString {
    var result = AttributedString(string)
    if !intent.isEmpty { result.inlinePresentationIntent = intent }
    if let link { result.link = link }
    return result
  }

  /// 相对地址按网站解析（/posts/… 是站内链接）；页内锚点（#…）App 里跳不过去，不做成链接
  static func resolve(_ destination: String) -> URL? {
    guard !destination.hasPrefix("#"), let url = URL(string: destination, relativeTo: SiteLinks.siteURL)?.absoluteURL else { return nil }
    return isSafe(url) ? url : nil
  }

  /// 和网站渲染前的 sanitize 一样，只放行这几种协议（javascript: 之类一律丢掉）
  static func isSafe(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return ["http", "https", "mailto"].contains(scheme)
  }
}

private final class BracketCounter {
  var count = 0
}

extension AttributedString {
  func applying(_ intent: InlinePresentationIntent) -> AttributedString {
    var result = self
    for run in result.runs {
      let current = run.inlinePresentationIntent ?? []
      result[run.range].inlinePresentationIntent = current.union(intent)
    }
    return result
  }
}

extension String {
  func trimmingTrailingNewlines() -> String {
    var result = self
    while result.last?.isNewline == true { result.removeLast() }
    return result
  }
}
