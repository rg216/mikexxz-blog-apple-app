# 博客的 Apple 客户端

## 目标
[网站](https://github.com/rg216/mikexzx-blog)前台的原生 App：iPhone、iPad、Mac 一套 SwiftUI 代码。和网站一样，学习是目的：
能自己实现的刻意自己实现（Markdown 渲染、裸网址识别），做非显而易见的设计决策时说明理由和权衡。遵循 Apple HIG。

## 结构
- `Blog/`：App 本体（一个多平台 target：iOS + iPadOS + 原生 macOS，不是 Catalyst）。Xcode 16 起的同步文件夹（synchronized folder）：新建文件不用改 project.pbxproj
- `BlogKit/`：本地 Swift 包，与界面无关的部分——接口模型、API 客户端、Markdown 解析、网址与日期规则。`cd BlogKit && swift test` 直接在 Mac 上跑，不用模拟器
- `BlogUITests/`：端到端（XCUITest），连线上 API，每步截图附在测试结果里
- `Config/Info.plist`：只放构建设置表达不了的键（ATS）；其余由 `GENERATE_INFOPLIST_FILE` 生成
- `scripts/`：图标生成、裸网址对照数据生成
- Xcode 工程最初用 XcodeGen 生成，之后以 `Blog.xcodeproj` 为准、在 Xcode 里维护（没有 project.yml）

## 约定
- Xcode 27（SDK 27.x），部署目标 iOS / macOS 27.0；Swift 6 语言模式，App target 默认 MainActor 隔离（`SWIFT_DEFAULT_ACTOR_ISOLATION`）+ Approachable Concurrency
- 命令行的 `swift` 来自 swiftly（2026-10：6.4.1）。它的版本不能低于 Xcode 自带的 Swift（Xcode 27 是 6.4）：6.3.1 配 Xcode 27 的 SDK 编译 Package.swift 就崩（`unknown argument: -target-arch-variant`）。拿不准时用 `xcrun swift`（Xcode 自带的工具链）。`swiftly use` 不加 `--global-default` 会在当前目录写 `.swift-version`
- 依赖只有 Apple 维护的 swift-markdown；引入新依赖前先确认仍在维护
- 模型和网站 `packages/shared` 的 zod schema 一一对应（字段名相同）。不用 enum 表示网站可能扩展的值（语言 `ContentLocale`、错误码 `APIErrorCode`）：App 装在读者手机上可能很久不更新，enum 遇到新值会让整个响应解码失败
- 界面文案：`Blog/Resources/Localizable.xcstrings`，源语言英文，另有 zh-Hans、ja；措辞尽量和网站的字典一致。API 返回的中文 message 不给读者看，按错误原因显示本地化文案
- 设计：系统文本样式（Dynamic Type）、语义色、SF Symbols（原生 App 可以用；网站不行）、`.continuous` 圆角；不自定义 accent color（macOS 上尊重用户选的强调色）。版面宽度沿用网站：正文 680、出血图片 864
- App 图标不能用 SF Symbols 或 SF 字体（许可证不允许）

## 和 API 的关系
- 直接请求 API 项目（`BlogClient.productionURL`），不经过网站的 `/api` 代理：代理是为了浏览器的第一方 cookie 和 Passkey，App 不需要。限流按 `X-Forwarded-For` 第一项，直连时就是读者的 IP
- 本地开发：scheme 的环境变量 `BLOG_API_URL=http://localhost:8787`（默认禁用，在 Edit Scheme 里勾上）；ATS 只对本机放开明文 HTTP
- 离线：API 的响应是 `max-age=0, must-revalidate`，URLCache 照样存着；连不上时退回缓存（`BlogClient.get`）。评论、阅读数不走缓存
- 阅读数只读不计：计数接口是写请求，API 要求 `Origin` 等于网站的源（CSRF 防护），App 发不出。要计入 App 的阅读，需要 API 为这个不带 cookie 的接口放开 Origin 检查
- 评论只读：网站的 GitHub 登录是 OAuth 回跳 + `__Host-` cookie。App 里要用 ASWebAuthenticationSession + 不靠 cookie 的凭证，API 也要改；目前引导去网页评论

## 渲染
- 文章语言：读者在工具栏的地球菜单里选（macOS 另有"设置"窗口），第一次按界面语言；每篇文章还可以单独切换语言。界面语言跟随系统
- 时间按站点时区（Asia/Shanghai）显示和分组，和网页一致
- Markdown：swift-markdown 解析成块（`MarkdownDocument`），行内内容转成只带 Foundation 属性的 AttributedString（SwiftUI 的 Text 原生认识粗体 / 斜体 / 代码 / 删除线 / 链接）；块到视图在 `Blog/Markdown/`
- 裸网址：swift-markdown 没挂 cmark-gfm 的 autolink 扩展，`LiteralAutolinks` 移植了网站实际用的 micromark 分词器 + mdast 的正则补找两遍规则（包括"网址。"把句号算进链接的怪癖）。`BlogKitTests/Fixtures/autolinks.json` 由 `scripts/generate-autolink-fixtures.mjs` 用网站的 remark-gfm 生成（`node scripts/generate-autolink-fixtures.mjs ../mikexxz-blog > BlogKit/Tests/BlogKitTests/Fixtures/autolinks.json`），逐条对照；已知不一致见 `AutolinkFixtureTests.isKnownDifference`
- 图片：按网站的约定读 `#small` / `#medium` / `#large` / `#w=` 片段和媒体库 key，按显示宽度 × 屏幕倍率挑尺寸版本；不放大、竖图不超过视口 80%
- 正文里指向本站文章 / 标签页的链接在 App 内打开（`RoutedStack` 的 openURL），语言按读者的设置
- 中日共用汉字：文章、标题、标签按内容的语言设 `typesettingLanguage`（网页上 `lang` 的作用）

## 常用命令
- `cd BlogKit && swift test`：模型、解析、裸网址对照
- `xcodebuild -project Blog.xcodeproj -scheme Blog -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`：端到端（连线上 API）
- macOS 的 UI 测试第一次要在系统弹窗里授权自动化；签名：在 Xcode 的 Signing & Capabilities 里选自己的 Team（工程里没写死）
