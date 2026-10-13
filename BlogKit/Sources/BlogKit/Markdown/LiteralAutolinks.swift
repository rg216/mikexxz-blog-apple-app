import Foundation

/// GFM 的字面自动链接（裸网址、www.、邮箱）。
///
/// swift-markdown 只挂了 cmark-gfm 的表格、删除线、任务列表扩展，没有 autolink，裸网址不会成为链接。
/// 网站用 micromark（remark-gfm）渲染，这里逐条移植 micromark-extension-gfm-autolink-literal 2.1 的规则，
/// 让 App 里哪些文字是链接、链接到哪里和网页上完全一致——包括它的怪癖：
/// "详见 https://a.b/c。" 的链接是 `https://a.b/c。`（路径只在空白处结束，非 ASCII 标点不算结尾），
/// 网页上读者点开也是这个地址；网站的翻译结构校验正是按这个结果比较原文和译文的链接。
///
/// 网站上其实是两遍：先是 micromark 的分词（`tokenizerMatches`），再由 mdast-util-gfm-autolink-literal 2.0
/// 用正则在剩下的文字节点里补找一遍（`regexMatches`，原本是为了没配对的 "[" 后面分词器不认的网址）。
/// 两遍的规则不一样（比如 "www." 第二遍会变成指向 http://www 的链接），都照搬。
///
/// 分词器在还没配对的 "[" 之后不找链接（那时还不知道它会不会成为链接文字），由第二遍去找，
/// 规则不同（"[https://a.b/c_" 的链接带着结尾的 "_"）；所以要记住段落里有几个没配对的 "["（`openBrackets`）。
///
/// 和网站的差别：分词器在整段文字流上判断前一个字符，这里在每一段连续的纯文字里判断，段首视为行首；
/// 转义的 `\[` 在这里也算括号。都是很少见的写法。
enum LiteralAutolinks {
  struct Match: Equatable {
    /// 在 Unicode 标量数组里的范围
    let range: Range<Int>
    let url: String
  }

  /// openBrackets：同一段落里此前还没配对的 "[" 的个数，跨文字片段累计（片段之间隔着强调、行内代码等）
  static func matches(in text: String, openBrackets: inout Int) -> [Match] {
    let chars = Array(text.unicodeScalars)
    var result: [Match] = []
    // 第二遍只在第一遍的链接之间的文字里找，每段文字的开头算"前面没有字符"
    var cursor = 0
    for match in tokenizerMatches(chars, openBrackets: &openBrackets) + [Match(range: chars.count..<chars.count, url: "")] {
      result += regexMatches(chars, cursor..<match.range.lowerBound)
      if !match.range.isEmpty { result.append(match) }
      cursor = match.range.upperBound
    }
    return result
  }

  // MARK: - 第一遍：micromark-extension-gfm-autolink-literal 2.1 的分词器

  static func tokenizerMatches(_ chars: [Unicode.Scalar], openBrackets: inout Int) -> [Match] {
    var result: [Match] = []
    var index = 0
    while index < chars.count {
      // 走到这里的 "]" 都没能组成链接（成了的话 cmark 已经把它变成链接节点），micromark 把它对应的 "[" 标为已配对
      if chars[index] == "[" {
        openBrackets += 1
        index += 1
        continue
      }
      if chars[index] == "]", openBrackets > 0 {
        openBrackets -= 1
        index += 1
        continue
      }
      guard openBrackets == 0 else {
        index += 1
        continue
      }
      let previous = index > 0 ? chars[index - 1] : nil
      // micromark 对同一个起始字符依次尝试：先邮箱，再协议 / www
      if let end = email(chars, index, previous) {
        result.append(Match(range: index..<end, url: "mailto:" + string(chars, index..<end)))
        index = end
      } else if let end = proto(chars, index, previous) {
        result.append(Match(range: index..<end, url: string(chars, index..<end)))
        index = end
      } else if let end = www(chars, index, previous) {
        result.append(Match(range: index..<end, url: "http://" + string(chars, index..<end)))
        index = end
      } else {
        index += 1
      }
    }
    return result
  }

  // MARK: - 第二遍：mdast-util-gfm-autolink-literal 2.0 的 transformGfmAutolinkLiterals

  /// 先用网址的正则 `/(https?:\/\/|www(?=\.))([-.\w]+)([^ \t\r\n]*)/gi` 切分，再在切剩的文字里找邮箱
  /// （mdast-util-find-and-replace 逐个模式处理，后一个模式只看前一个留下的文字节点）
  static func regexMatches(_ chars: [Unicode.Scalar], _ range: Range<Int>) -> [Match] {
    var result: [Match] = []
    var cursor = range.lowerBound
    for match in regexURLs(chars, range) + [Match(range: range.upperBound..<range.upperBound, url: "")] {
      result += regexEmails(chars, cursor..<match.range.lowerBound)
      if !match.range.isEmpty { result.append(match) }
      cursor = match.range.upperBound
    }
    return result
  }

  private static func regexURLs(_ chars: [Unicode.Scalar], _ range: Range<Int>) -> [Match] {
    var result: [Match] = []
    var index = range.lowerBound
    while index < range.upperBound {
      guard let found = regexURL(chars, at: index, in: range) else {
        index += 1
        continue
      }
      // findUrl 返回 false 时从下一个字符接着找（lastIndex = index + 1），否则从整个匹配之后
      if regexPrevious(chars, index, in: range, email: false), let link = found.link {
        result.append(link)
        index = found.end
      } else {
        index += 1
      }
    }
    return result
  }

  /// 在 index 处尝试匹配网址正则；匹配上时 end 是整个匹配（含结尾标点）的末尾，link 是 findUrl 的结果
  private static func regexURL(_ chars: [Unicode.Scalar], at start: Int, in range: Range<Int>) -> (end: Int, link: Match?)? {
    func lower(_ i: Int) -> Unicode.Scalar? { i < range.upperBound ? Unicode.Scalar(chars[i].properties.lowercaseMapping) : nil }
    var index = start
    var isWww = false
    if lower(index) == "h", lower(index + 1) == "t", lower(index + 2) == "t", lower(index + 3) == "p" {
      index += 4
      if lower(index) == "s" { index += 1 }
      guard lower(index) == ":", lower(index + 1) == "/", lower(index + 2) == "/" else { return nil }
      index += 3
    } else if lower(index) == "w", lower(index + 1) == "w", lower(index + 2) == "w", lower(index + 3) == "." {
      index += 3
      isWww = true
    } else {
      return nil
    }
    let protocolEnd = index
    while index < range.upperBound, isRegexDomainChar(chars[index]) { index += 1 }
    guard index > protocolEnd else { return nil }
    let domainEnd = index
    while index < range.upperBound, !" \t\r\n".unicodeScalars.contains(chars[index]) { index += 1 }
    let end = index

    let domainStart = isWww ? start : protocolEnd
    guard isCorrectDomain(string(chars, domainStart..<domainEnd)) else { return (end, nil) }
    let linkEnd = splitURL(chars, domainStart..<end)
    guard linkEnd > domainStart else { return (end, nil) }
    let text = string(chars, start..<linkEnd)
    return (end, Match(range: start..<linkEnd, url: isWww ? "http://" + text : text))
  }

  /// findEmail：`(?<=^|\s|\p{P}|\p{S})([-.\w+]+)@([-\w]+(?:\.[-\w]+)+)`，标签不能以 - 数字 _ 结尾
  private static func regexEmails(_ chars: [Unicode.Scalar], _ range: Range<Int>) -> [Match] {
    var result: [Match] = []
    var index = range.lowerBound
    while index < range.upperBound {
      if regexPrevious(chars, index, in: range, email: true), let end = regexEmail(chars, at: index, in: range) {
        result.append(Match(range: index..<end, url: "mailto:" + string(chars, index..<end)))
        index = end
      } else {
        index += 1
      }
    }
    return result
  }

  private static func regexEmail(_ chars: [Unicode.Scalar], at start: Int, in range: Range<Int>) -> Int? {
    var index = start
    while index < range.upperBound, isRegexWord(chars[index]) || "-.+".unicodeScalars.contains(chars[index]) { index += 1 }
    guard index > start, index < range.upperBound, chars[index] == "@" else { return nil }
    index += 1
    // 标签：一段或多段 [-\w]+，至少有一个点；贪婪匹配，结尾的点不算
    var segments = 0
    var end = index
    while true {
      let segmentStart = index
      while index < range.upperBound, isRegexWord(chars[index]) || chars[index] == "-" { index += 1 }
      guard index > segmentStart else { break }
      segments += 1
      end = index
      guard index < range.upperBound, chars[index] == "." else { break }
      index += 1
    }
    guard segments >= 2 else { return nil }
    let last = chars[end - 1]
    if last == "-" || last == "_" || ("0"..."9").contains(last) { return nil }
    return end
  }

  /// 前一个字符是开头、空白或标点 / 符号（邮箱另外不能是 "/"）。
  /// 网站按 UTF-16 码元取前一个字符：前面是 emoji 这类代理对时取到的是低位代理，不算标点
  private static func regexPrevious(_ chars: [Unicode.Scalar], _ index: Int, in range: Range<Int>, email: Bool) -> Bool {
    guard index > range.lowerBound else { return true }
    let previous = chars[index - 1]
    if previous.value > 0xFFFF { return false }
    return (previous.properties.isWhitespace || isPunctuation(previous)) && !(email && previous == "/")
  }

  /// 最后两段不能有下划线，且要有字母或数字（空的段跳过检查）
  private static func isCorrectDomain(_ domain: String) -> Bool {
    let parts = domain.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2 else { return false }
    for part in parts.suffix(2) where !part.isEmpty {
      if part.contains("_") || !part.unicodeScalars.contains(where: isAsciiAlphanumeric) { return false }
    }
    return true
  }

  /// splitUrl：去掉末尾的 `[!"&'),.:;<>?\]}]+`，但配对的 ")" 留下
  private static func splitURL(_ chars: [Unicode.Scalar], _ range: Range<Int>) -> Int {
    var end = range.upperBound
    while end > range.lowerBound, "!\"&'),.:;<>?]}".unicodeScalars.contains(chars[end - 1]) { end -= 1 }
    let opening = chars[range.lowerBound..<end].count { $0 == "(" }
    var closing = chars[range.lowerBound..<end].count { $0 == ")" }
    var trail = end
    while opening > closing, let paren = chars[trail..<range.upperBound].firstIndex(of: ")") {
      trail = paren + 1
      end = trail
      closing += 1
    }
    return end
  }

  /// JS 正则的 \w：只有 ASCII
  private static func isRegexWord(_ char: Unicode.Scalar) -> Bool {
    isAsciiAlphanumeric(char) || char == "_"
  }

  private static func isRegexDomainChar(_ char: Unicode.Scalar) -> Bool {
    isRegexWord(char) || char == "-" || char == "."
  }

  // MARK: - 三种链接

  private static func email(_ chars: [Unicode.Scalar], _ start: Int, _ previous: Unicode.Scalar?) -> Int? {
    guard isAtext(chars[start]), previousEmail(previous) else { return nil }
    var index = start
    while index < chars.count, isAtext(chars[index]) { index += 1 }
    guard index < chars.count, chars[index] == "@" else { return nil }
    index += 1
    var data = false
    var dot = false
    while index < chars.count {
      let char = chars[index]
      if char == "." {
        // 点后面紧跟字母或数字才算域名的一部分，否则是句末的句号
        guard index + 1 < chars.count, isAsciiAlphanumeric(chars[index + 1]) else { break }
        dot = true
        index += 1
      } else if char == "-" || char == "_" || isAsciiAlphanumeric(char) {
        data = true
        index += 1
      } else {
        break
      }
    }
    guard data, dot, isAsciiAlpha(chars[index - 1]) else { return nil }
    return index
  }

  private static func proto(_ chars: [Unicode.Scalar], _ start: Int, _ previous: Unicode.Scalar?) -> Int? {
    guard chars[start] == "h" || chars[start] == "H", previousProtocol(previous) else { return nil }
    var index = start + 1
    var scheme = String(chars[start])
    while index < chars.count, isAsciiAlpha(chars[index]), scheme.count < 5 {
      scheme.unicodeScalars.append(chars[index])
      index += 1
    }
    guard index < chars.count, chars[index] == ":", ["http", "https"].contains(scheme.lowercased()) else { return nil }
    index += 1
    guard index + 1 < chars.count, chars[index] == "/", chars[index + 1] == "/" else { return nil }
    index += 2
    guard index < chars.count else { return nil }
    let first = chars[index]
    if isAsciiControl(first) || isSpace(first) || isPunctuation(first) { return nil }
    guard let afterDomain = domain(chars, index) else { return nil }
    return path(chars, afterDomain)
  }

  private static func www(_ chars: [Unicode.Scalar], _ start: Int, _ previous: Unicode.Scalar?) -> Int? {
    guard previousWww(previous), start + 4 < chars.count else { return nil }
    for offset in 0..<3 where chars[start + offset] != "w" && chars[start + offset] != "W" { return nil }
    guard chars[start + 3] == "." else { return nil }
    guard let afterDomain = domain(chars, start) else { return nil }
    return path(chars, afterDomain)
  }

  // MARK: - 组成部分

  /// 域名：到空白或（连字符以外的）标点为止；最后两段不能有下划线
  private static func domain(_ chars: [Unicode.Scalar], _ start: Int) -> Int? {
    var index = start
    var underscoreInLast = false
    var underscoreInLastButOne = false
    var seen = false
    while index < chars.count {
      let char = chars[index]
      if char == "." || char == "_" {
        if isTrail(chars, index) { break }
        if char == "_" {
          underscoreInLast = true
        } else {
          underscoreInLastButOne = underscoreInLast
          underscoreInLast = false
        }
        index += 1
        continue
      }
      if isSpace(char) || (char != "-" && isPunctuation(char)) { break }
      seen = true
      index += 1
    }
    guard seen, !underscoreInLast, !underscoreInLastButOne else { return nil }
    return index
  }

  /// 路径：到空白为止；末尾的 ASCII 标点、不配对的 ")" 不算
  private static func path(_ chars: [Unicode.Scalar], _ start: Int) -> Int {
    var index = start
    var open = 0
    var close = 0
    while index < chars.count {
      let char = chars[index]
      if char == "(" {
        open += 1
        index += 1
        continue
      }
      if char == ")" && close < open {
        close += 1
        index += 1
        continue
      }
      if "!\"&')*,.:;<?]_~".unicodeScalars.contains(char) {
        if isTrail(chars, index) { return index }
        if char == ")" { close += 1 }
        index += 1
        continue
      }
      if isSpace(char) { return index }
      index += 1
    }
    return index
  }

  /// 从 index 开始是否只剩"结尾标点"（之后是空白、"<" 或文字结束）
  private static func isTrail(_ chars: [Unicode.Scalar], _ start: Int) -> Bool {
    var index = start
    while true {
      guard index < chars.count else { return true }
      let char = chars[index]
      if "!\"')*,.:;?_~".unicodeScalars.contains(char) {
        index += 1
      } else if char == "&" {
        // 具名字符引用 &nbsp; 也算结尾
        index += 1
        guard index < chars.count, isAsciiAlpha(chars[index]) else { return false }
        while index < chars.count, isAsciiAlpha(chars[index]) { index += 1 }
        guard index < chars.count, chars[index] == ";" else { return false }
        index += 1
      } else if char == "]" {
        index += 1
        guard index < chars.count else { return true }
        let next = chars[index]
        if next == "(" || next == "[" || isSpace(next) { return true }
      } else {
        return char == "<" || isSpace(char)
      }
    }
  }

  // MARK: - 前一个字符

  private static func previousWww(_ char: Unicode.Scalar?) -> Bool {
    guard let char else { return true }
    return "(*_[]~".unicodeScalars.contains(char) || isMarkdownSpace(char)
  }

  private static func previousProtocol(_ char: Unicode.Scalar?) -> Bool {
    guard let char else { return true }
    return !isAsciiAlpha(char)
  }

  private static func previousEmail(_ char: Unicode.Scalar?) -> Bool {
    guard let char else { return true }
    return !(char == "/" || isAtext(char))
  }

  // MARK: - 字符类别（micromark-util-character）

  private static func isAtext(_ char: Unicode.Scalar) -> Bool {
    char == "+" || char == "-" || char == "." || char == "_" || isAsciiAlphanumeric(char)
  }

  private static func isAsciiAlpha(_ char: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(char) || ("A"..."Z").contains(char)
  }

  private static func isAsciiAlphanumeric(_ char: Unicode.Scalar) -> Bool {
    isAsciiAlpha(char) || ("0"..."9").contains(char)
  }

  private static func isAsciiControl(_ char: Unicode.Scalar) -> Bool {
    char.value < 32 || char.value == 127
  }

  private static func isMarkdownSpace(_ char: Unicode.Scalar) -> Bool {
    char == " " || char == "\t" || char == "\n" || char == "\r"
  }

  /// markdownLineEndingOrSpace 或 unicodeWhitespace（/\s/）
  private static func isSpace(_ char: Unicode.Scalar) -> Bool {
    isMarkdownSpace(char) || char.properties.isWhitespace
  }

  /// /\p{P}|\p{S}/u：Unicode 标点和符号（含 ASCII 的）
  private static func isPunctuation(_ char: Unicode.Scalar) -> Bool {
    switch char.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
      .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
      true
    default:
      false
    }
  }

  private static func string(_ chars: [Unicode.Scalar], _ range: Range<Int>) -> String {
    var result = ""
    result.unicodeScalars.append(contentsOf: chars[range])
    return result
  }
}
