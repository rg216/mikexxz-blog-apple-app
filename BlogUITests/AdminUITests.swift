import XCTest

/// 后台：连本地 API（`bun run dev`），token 由测试运行时的环境变量注入，跳过网页登录（Passkey 没法在测试里点）：
///
///     TEST_RUNNER_BLOG_ADMIN_TOKEN=<token> xcodebuild test -only-testing:BlogUITests/AdminUITests …
///
/// token 是本地开发库里的一个 session（见 CLAUDE.md "测试后台"）。没设时这个测试失败并说明原因
final class AdminUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor func testBrowseAdminPages() throws {
    let token = try XCTUnwrap(ProcessInfo.processInfo.environment["BLOG_ADMIN_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }, "没有设置 TEST_RUNNER_BLOG_ADMIN_TOKEN")
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-contentLocale", "zh"]
    app.launchEnvironment["BLOG_API_URL"] = ProcessInfo.processInfo.environment["BLOG_API_URL"] ?? "http://localhost:8787"
    app.launchEnvironment["BLOG_ADMIN_TOKEN"] = token
    app.launch()

    press(tab(app, "后台"))
    XCTAssertTrue(app.staticTexts["已登录"].waitForExistence(timeout: 15), "没有登录状态")
    snapshot(app, "admin-0-home")

    for (index, page) in ["文章", "标签", "评论", "媒体库", "系统状态", "Passkey", "设置"].enumerated() {
      press(row(app, page))
      sleep(3)
      snapshot(app, "admin-\(index + 1)-\(page)")
      if page == "文章" {
        let first = app.descendants(matching: .any).matching(identifier: "admin-post-row").firstMatch
        if first.waitForExistence(timeout: 5) {
          press(first)
          sleep(3)
          snapshot(app, "admin-1b-文章编辑")
          back(app)
        }
      }
      if page == "标签" {
        let first = app.descendants(matching: .any).matching(identifier: "admin-tag-row").firstMatch
        if first.waitForExistence(timeout: 5) {
          press(first)
          sleep(2)
          snapshot(app, "admin-2b-标签编辑")
          press(app.buttons["取消"].firstMatch)
          sleep(1)
        }
      }
      back(app)
    }
  }

  /// 写入路径：新建标签 → 列表里出现 → 删除。验证 App 发出的请求体 API 认得
  @MainActor func testCreateAndDeleteTag() throws {
    let app = try launchSignedIn()
    press(row(app, "标签"))
    press(app.buttons["新建标签"].firstMatch)
    let suffix = Int.random(in: 1000...9999)
    let slug = "ui-test-\(suffix)"
    type(app.textFields["名称（中文）"].firstMatch, "界面测试\(suffix)")
    type(app.textFields["slug"].firstMatch, slug)
    type(app.textFields["英语名称"].firstMatch, "UI test \(suffix)")
    type(app.textFields["日语名称"].firstMatch, "UIテスト\(suffix)")
    press(app.buttons["保存"].firstMatch)
    let created = app.staticTexts["#\(slug)"].firstMatch
    if !created.waitForExistence(timeout: 10) {
      snapshot(app, "admin-tag-not-created")
      XCTFail("新标签没有出现在列表里")
    }
    snapshot(app, "admin-tag-created")

    for _ in 0..<6 where !created.isHittable { app.swipeUp() }
    created.swipeLeft()
    press(app.buttons["删除"].firstMatch)
    press(app.buttons["删除"].firstMatch)
    XCTAssertTrue(waitForDisappearance(created, timeout: 10), "标签没有删掉")
  }

  /// 新建草稿 → 保存英语译文（人工）→ 删除文章
  @MainActor func testDraftPostWithTranslation() throws {
    let app = try launchSignedIn()
    press(row(app, "文章"))
    press(app.buttons["写文章"].firstMatch)
    let slug = "ui-test-\(Int.random(in: 1000...9999))"
    type(app.textFields["标题"].firstMatch, "界面测试文章 \(slug)")
    type(app.textFields["slug（网址）"].firstMatch, slug)
    let body = app.textViews.firstMatch
    press(body)
    body.typeText("这是界面测试写的正文。")
    press(app.buttons["保存"].firstMatch)
    XCTAssertTrue(app.staticTexts["已保存为草稿。"].waitForExistence(timeout: 10), "草稿没有保存")
    snapshot(app, "admin-post-saved")

    // 译文
    app.swipeUp()
    app.swipeUp()
    press(app.buttons.containing(.staticText, identifier: "英语").firstMatch)
    let title = app.textFields["标题"].firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    type(title, "UI test post")
    let translation = app.textViews.firstMatch
    press(translation)
    translation.typeText("Body written by the UI test.")
    press(app.buttons["保存"].firstMatch)
    XCTAssertTrue(app.staticTexts["已保存为人工译文。"].waitForExistence(timeout: 10), "译文没有保存")
    snapshot(app, "admin-translation-saved")
    back(app)

    // 删除文章（连同译文）
    sleep(2)
    #if os(iOS)
      // 工具栏放不下的按钮收在"更多"里（界面是中文，按钮名也是中文）
      app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["更多", "More"])).firstMatch.tap()
    #endif
    press(app.buttons["删除文章"].firstMatch)
    press(app.buttons["删除文章和所有译文"].firstMatch)
    XCTAssertTrue(app.staticTexts["界面测试文章 \(slug)"].waitForNonExistence(timeout: 10), "文章没有删掉")
  }

  @MainActor private func launchSignedIn() throws -> XCUIApplication {
    let token = try XCTUnwrap(ProcessInfo.processInfo.environment["BLOG_ADMIN_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }, "没有设置 TEST_RUNNER_BLOG_ADMIN_TOKEN")
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-contentLocale", "zh"]
    app.launchEnvironment["BLOG_API_URL"] = ProcessInfo.processInfo.environment["BLOG_API_URL"] ?? "http://localhost:8787"
    app.launchEnvironment["BLOG_ADMIN_TOKEN"] = token
    app.launch()
    press(tab(app, "后台"))
    XCTAssertTrue(app.staticTexts["已登录"].waitForExistence(timeout: 15), "没有登录状态")
    return app
  }

  @MainActor private func type(_ field: XCUIElement, _ text: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 10), "找不到输入框")
    press(field)
    field.typeText(text)
  }

  @MainActor private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    element.waitForNonExistence(timeout: timeout)
  }

  /// 后台目录里的一行（"文章""标签"和标签栏里的读者页面同名，只在列表里找）
  @MainActor private func row(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    #if os(iOS)
      let list = app.collectionViews.firstMatch
      let target = list.buttons[label].firstMatch
      if !target.isHittable { list.swipeUp() }
      return target
    #else
      return app.outlines.buttons[label].firstMatch
    #endif
  }

  @MainActor private func back(_ app: XCUIApplication) {
    #if os(iOS)
      app.navigationBars.buttons.element(boundBy: 0).tap()
    #else
      app.typeKey("[", modifierFlags: .command)
    #endif
    sleep(1)
  }

  @MainActor private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    let button = app.buttons[label].firstMatch
    if button.exists { return button }
    return app.cells.containing(.staticText, identifier: label).firstMatch
  }

  @MainActor private func press(_ element: XCUIElement) {
    #if os(macOS)
      element.click()
    #else
      element.tap()
    #endif
  }

  @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
