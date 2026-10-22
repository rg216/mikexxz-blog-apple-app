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

  /// 切换到别的标签页再回来，后台还要能点：Mac 上曾经回来以后点列表没反应
  @MainActor func testAdminSurvivesTabSwitch() throws {
    let app = try launchSignedIn()
    let hierarchy = XCTAttachment(string: app.debugDescription)
    hierarchy.name = "hierarchy-home"
    hierarchy.lifetime = .keepAlways
    add(hierarchy)

    // 在后台的某一页里切走再回来
    press(row(app, "文章"))
    let post = app.descendants(matching: .any).matching(identifier: "admin-post-row").firstMatch
    XCTAssertTrue(post.waitForExistence(timeout: 10), "文章列表没有加载出来")
    press(sidebarTab(app, "归档"))
    sleep(2)
    press(sidebarTab(app, "后台"))
    sleep(2)
    snapshot(app, "admin-switch-1-back-in-posts")
    // 回来时应该还停在文章列表；如果被打回了目录，点"文章"要能再进去
    if !post.exists {
      press(row(app, "文章"))
      sleep(2)
      snapshot(app, "admin-switch-1b-clicked-posts-again")
      XCTAssertTrue(post.waitForExistence(timeout: 10), "切回来以后被打回目录，再点“文章”也进不去")
    }
    press(post)
    sleep(2)
    snapshot(app, "admin-switch-2-opened-post")
    XCTAssertTrue(app.staticTexts["编辑文章"].firstMatch.waitForExistence(timeout: 5) || app.textFields["标题"].firstMatch.exists, "切回来以后点文章没反应")
    back(app)
    back(app)

    // 在后台目录切走再回来
    press(sidebarTab(app, "标签"))
    sleep(2)
    press(sidebarTab(app, "后台"))
    sleep(2)
    snapshot(app, "admin-switch-3-back-home")
    press(row(app, "标签"))
    let tag = app.descendants(matching: .any).matching(identifier: "admin-tag-row").firstMatch
    XCTAssertTrue(tag.waitForExistence(timeout: 10), "切回来以后点标签没反应")
    snapshot(app, "admin-switch-4-tags")
  }

  /// 读者标签页里打开一篇文章，切到后台再切回来，再到后台里点开一页：
  /// Mac 上各标签页共用侧边栏的同一个详情栏，导航路径类型不同（[Route] / [AdminRoute]）时曾经崩溃
  @MainActor func testSwitchingBetweenReaderAndAdminTabs() throws {
    let app = try launchSignedIn()
    press(sidebarTab(app, "文章"))
    let readerPost = app.descendants(matching: .any).matching(identifier: "post-row").firstMatch
    XCTAssertTrue(readerPost.waitForExistence(timeout: 15), "文章列表没有加载出来")
    press(readerPost)
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "article-title").firstMatch.waitForExistence(timeout: 15), "文章没有打开")
    press(sidebarTab(app, "后台"))
    sleep(2)
    press(row(app, "标签"))
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "admin-tag-row").firstMatch.waitForExistence(timeout: 10), "后台标签页没有打开")
    press(sidebarTab(app, "文章"))
    sleep(2)
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "article-title").firstMatch.waitForExistence(timeout: 15), "切回来以后文章没有还原")
    snapshot(app, "switch-reader-restored")
    press(sidebarTab(app, "后台"))
    sleep(2)
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "admin-tag-row").firstMatch.waitForExistence(timeout: 10), "切回后台以后标签页没有还原")
    snapshot(app, "switch-admin-restored")
  }

  /// Mac 上的字号（不截图，读文字控件的高度）：列表行、表单里的文字要用放大后的字号（Font.app、rowFont、
  /// AppLabeledContentStyle）。正文 13pt（系统默认）的文字高约 16，15pt 约 18–19；脚注 11pt 约 14，12pt 约 15。
  /// iOS 上不检查：那里的字号跟随 Dynamic Type，没有固定值
  @MainActor func testTextSizes() throws {
    #if !os(macOS)
      throw XCTSkip("只在 Mac 上检查字号")
    #else
      let app = try launchSignedIn()
      func height(_ label: String) -> CGFloat {
        let element = app.staticTexts[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "找不到“\(label)”")
        return element.frame.height
      }
      XCTAssertGreaterThanOrEqual(height("文章"), 18, "列表行（导航）")
      XCTAssertGreaterThanOrEqual(height("已登录"), 18, "列表行（LabeledContent）")
      XCTAssertGreaterThanOrEqual(height("闲置 7 天或登录满 30 天后需要重新登录。"), 15, "Section 页脚")
      press(row(app, "文章"))
      let post = app.descendants(matching: .any).matching(identifier: "admin-post-row").firstMatch
      XCTAssertTrue(post.waitForExistence(timeout: 10))
      press(post)
      XCTAssertGreaterThanOrEqual(height("状态"), 18, "表单里的 Picker")
      XCTAssertGreaterThanOrEqual(height("首次发布"), 18, "表单里的 LabeledContent")
    #endif
  }

  /// 顶层的标签页：iPhone 上是标签栏按钮，Mac 上是侧边栏的一行（后台目录里也有"文章""标签"，不能混）
  @MainActor private func sidebarTab(_ app: XCUIApplication, _ label: String) -> XCUIElement {
    #if os(macOS)
      return app.outlines.firstMatch.cells.containing(.staticText, identifier: label).firstMatch
    #else
      return app.tabBars.buttons[label].firstMatch
    #endif
  }

  @MainActor func testBrowseAdminPages() throws {
    let token = try XCTUnwrap(ProcessInfo.processInfo.environment["BLOG_ADMIN_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }, "没有设置 TEST_RUNNER_BLOG_ADMIN_TOKEN")
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-contentLocale", "zh", "-ApplePersistenceIgnoreState", "YES"]
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
      // 页面打开了不够，要真的加载出数据：Mac 上曾经一直转圈（后台客户端没传进推入的页面），只截图的测试照样通过
      if page == "文章" {
        let first = app.descendants(matching: .any).matching(identifier: "admin-post-row").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "文章列表没有加载出来")
        press(first)
        sleep(3)
        snapshot(app, "admin-1b-文章编辑")
        back(app)
      }
      if page == "标签" {
        let first = app.descendants(matching: .any).matching(identifier: "admin-tag-row").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "标签列表没有加载出来")
        press(first)
        sleep(2)
        snapshot(app, "admin-2b-标签编辑")
        press(app.buttons["取消"].firstMatch)
        sleep(1)
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
    let gone = app.staticTexts["界面测试文章 \(slug)"].waitForNonExistence(timeout: 10)
    if !gone { snapshot(app, "admin-post-not-deleted") }
    XCTAssertTrue(gone, "文章没有删掉")
  }

  /// 媒体库的"上传 → 从照片上传"要弹出系统的照片选择器（PhotosPicker 不能直接放在菜单里，见 MediaLibraryView）
  /// 生成头图：要在本地 API 里把 Claude 和 OpenAI 换成假的（不花钱），见 CLAUDE.md"测试后台"
  @MainActor func testGenerateCover() throws {
    let app = try launchSignedIn()
    press(row(app, "文章"))
    press(app.buttons["写文章"].firstMatch)
    type(app.textFields["标题"].firstMatch, "界面测试头图")
    let generate = app.buttons["generate-cover"].firstMatch
    for _ in 0..<3 where !generate.isHittable { app.swipeUp() }
    press(generate)

    // 第一步：Claude 写描述（标题、方向都带过去）
    let direction = app.textFields["cover-direction"].firstMatch
    XCTAssertTrue(direction.waitForExistence(timeout: 10), "生成头图的配置没有加载出来")
    type(direction, "暖色")
    press(app.buttons["用 Sonnet 5.5 写描述"].firstMatch)
    let prompt = app.textViews["cover-prompt"].firstMatch
    let written = NSPredicate { _, _ in (prompt.value as? String)?.contains("暖色") == true }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: written, object: nil)], timeout: 15), .completed, "画面描述没有填进来")
    snapshot(app, "cover-brief")

    // 第二步：出图。先试一次"停止"
    let start = app.buttons["cover-generate"].firstMatch
    #if os(macOS)
      // Mac 的 sheet 里 swipeUp 不滚动；按钮在底部工具栏后面时 isHittable 仍为真，直接滚到底
      app.sheets.firstMatch.scroll(byDeltaX: 0, deltaY: -1000)
    #else
      for _ in 0..<3 where !start.isHittable { app.swipeUp() }
    #endif
    press(start)
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '正在生成' OR value BEGINSWITH '正在生成'")).firstMatch.waitForExistence(timeout: 10), "没有显示生成进度")
    sleep(3)
    snapshot(app, "cover-generating")
    press(start)
    XCTAssertTrue(app.buttons["用 GPT Image 2.5 Flare 生成"].waitForExistence(timeout: 10), "停止之后按钮没有恢复")

    press(start)
    XCTAssertTrue(app.buttons["再生成一张"].waitForExistence(timeout: 40), "没有生成出图片")
    // 结果在表单下方：Form 只创建看得见的行，要滚过去
    let candidate = app.buttons["cover-candidate"].firstMatch
    #if os(macOS)
      app.sheets.firstMatch.scroll(byDeltaX: 0, deltaY: -1000)
    #else
      for _ in 0..<4 where !candidate.exists { app.swipeUp() }
    #endif
    XCTAssertTrue(candidate.waitForExistence(timeout: 5), "生成的图片没有显示在结果里")
    snapshot(app, "cover-generated")

    // 设为头图：上传进媒体库，sheet 关掉，编辑页显示头图
    press(app.buttons["设为头图"].firstMatch)
    XCTAssertTrue(app.buttons["移除头图"].waitForExistence(timeout: 30), "头图没有设上")
    snapshot(app, "cover-picked")
  }

  @MainActor func testCoverSettings() throws {
    let app = try launchSignedIn()
    press(row(app, "设置"))
    let style = app.textViews["cover-style"].firstMatch
    for _ in 0..<4 where !style.isHittable { app.swipeUp() }
    XCTAssertTrue(style.waitForExistence(timeout: 10), "设置里没有头图风格")
    XCTAssertTrue((style.value as? String)?.hasPrefix("Cover image for") == true)
    snapshot(app, "cover-settings")
  }

  @MainActor func testPhotoPickerOpens() throws {
    let app = try launchSignedIn()
    press(row(app, "媒体库"))
    press(app.buttons["上传"].firstMatch)
    press(app.buttons["从照片上传"].firstMatch)
    sleep(3)
    snapshot(app, "admin-photo-picker")
    // 照片选择器在另一个进程里显示，盖住了 App 自己的界面："上传"按钮不再可点
    XCTAssertFalse(app.buttons["上传"].firstMatch.isHittable, "照片选择器没有弹出来")
  }

  @MainActor private func launchSignedIn() throws -> XCUIApplication {
    let token = try XCTUnwrap(ProcessInfo.processInfo.environment["BLOG_ADMIN_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }, "没有设置 TEST_RUNNER_BLOG_ADMIN_TOKEN")
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-contentLocale", "zh", "-ApplePersistenceIgnoreState", "YES"]
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
      // SwiftUI 的 NavigationStack 在 Mac 上不响应 ⌘[，点工具栏的返回按钮
      app.toolbars.buttons.matching(NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch.click()
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
    // Mac 上只截 App 的窗口，不截整个屏幕
    #if os(macOS)
      let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    #else
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    #endif
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
