import XCTest

/// 端到端：连线上 API，走一遍主要页面，并把每一步的截图附在测试结果里（Xcode 的 Report navigator 里看，
/// 或 `xcrun xcresulttool export attachments`）。界面语言、文章语言用启动参数切换：
/// `-AppleLanguages (ja)` 是界面语言，`-contentLocale ja` 写进 UserDefaults 的参数域，覆盖文章语言的设置
final class BlogUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor func testBrowseInEnglish() {
    browse(uiLanguage: "en", contentLocale: "en", tabs: ["Tags", "Archive", "Search"], searchTerm: "blog")
  }

  @MainActor func testBrowseInChinese() {
    browse(uiLanguage: "zh-Hans", contentLocale: "zh", tabs: ["标签", "归档", "搜索"], searchTerm: "博客")
  }

  @MainActor func testBrowseInJapanese() {
    browse(uiLanguage: "ja", contentLocale: "ja", tabs: ["タグ", "アーカイブ", "検索"], searchTerm: "ブログ")
  }

  @MainActor private func browse(uiLanguage: String, contentLocale: String, tabs: [String], searchTerm: String) {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(\(uiLanguage))", "-contentLocale", contentLocale]
    app.launch()

    let firstPost = app.descendants(matching: .any).matching(identifier: "post-row").firstMatch
    XCTAssertTrue(firstPost.waitForExistence(timeout: 20), "文章列表没有加载出来")
    snapshot(app, "\(contentLocale)-1-posts")

    press(firstPost)
    let title = app.descendants(matching: .any).matching(identifier: "article-title").firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 20), "文章没有打开")
    sleep(2)  // 等图片
    snapshot(app, "\(contentLocale)-2-article")
    app.swipeUp()
    app.swipeUp()
    sleep(1)
    snapshot(app, "\(contentLocale)-3-article-body")
    for _ in 0..<6 { app.swipeUp() }
    sleep(2)
    snapshot(app, "\(contentLocale)-4-article-end")

    for (index, label) in tabs.enumerated() {
      press(tab(app, label))
      sleep(2)
      snapshot(app, "\(contentLocale)-\(5 + index)-tab")
    }

    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    press(field)
    field.typeText(searchTerm)
    sleep(3)
    snapshot(app, "\(contentLocale)-8-search")
  }

  /// 标签页按名称找：iPhone 底部、iPad 顶部的标签栏里是按钮，Mac 侧边栏里是一行
  @MainActor private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    let button = app.buttons[label].firstMatch
    if button.exists { return button }
    let cell = app.cells.containing(.staticText, identifier: label).firstMatch
    if cell.exists { return cell }
    return app.staticTexts[label].firstMatch
  }

  @MainActor private func press(_ element: XCUIElement) {
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }

  @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
    #if os(macOS)
      let screenshot = app.windows.firstMatch.screenshot()
    #else
      let screenshot = XCUIScreen.main.screenshot()
    #endif
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
