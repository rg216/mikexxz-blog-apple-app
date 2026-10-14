# 博客的 Apple 客户端

## 目标
[网站](https://github.com/rg216/mikexzx-blog)的原生 App（前台 + 后台）：iPhone、iPad、Mac 一套 SwiftUI 代码。和网站一样，学习是目的：
能自己实现的刻意自己实现（Markdown 渲染、裸网址识别），做非显而易见的设计决策时说明理由和权衡。遵循 Apple HIG。

## 结构
- `Blog/`：App 本体（一个多平台 target：iOS + iPadOS + 原生 macOS，不是 Catalyst）。Xcode 16 起的同步文件夹（synchronized folder）：新建文件不用改 project.pbxproj
- `BlogKit/`：本地 Swift 包，与界面无关的部分——接口模型、API 客户端、Markdown 解析、网址与日期规则。`cd BlogKit && swift test` 直接在 Mac 上跑，不用模拟器
- `BlogUITests/`：端到端（XCUITest），每步截图附在测试结果里。`BlogUITests` 连线上 API（只读）；`AdminUITests` 连本地 API（会写数据），见"测试后台"
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
- 工具栏按钮的标签里不要放转圈的 `ProgressView`（"保存中"换成文字）：iOS 27 上它移除之后动画还在跑，App 一直不"空闲"——耗电，UI 测试也会在每一步干等 15 分钟（2026-10 实测）

## 和 API 的关系
- 直接请求 API 项目（`BlogClient.productionURL`），不经过网站的 `/api` 代理：代理是为了浏览器的第一方 cookie 和 Passkey，App 不需要。限流按 `X-Forwarded-For` 第一项，直连时就是读者的 IP
- 本地开发：scheme 的环境变量 `BLOG_API_URL=http://localhost:8787`（默认禁用，在 Edit Scheme 里勾上）；ATS 只对本机放开明文 HTTP
- 离线：API 的响应是 `max-age=0, must-revalidate`，URLCache 照样存着；连不上时退回缓存（`BlogClient.get`）。评论、阅读数不走缓存
- 阅读数只读不计：计数接口是写请求，API 要求 `Origin` 等于网站的源（CSRF 防护），App 发不出。要计入 App 的阅读，需要 API 为这个不带 cookie 的接口放开 Origin 检查
- 评论只读：网站的 GitHub 登录是 OAuth 回跳 + `__Host-` cookie。App 里要用 ASWebAuthenticationSession + 不靠 cookie 的凭证，API 也要改；目前引导去网页评论

## 后台（"后台"标签页）
- 不登录也能进：里面的"设置"放着读者的文章语言（各列表工具栏里原来的地球菜单移到了这里；macOS 照平台惯例另有 ⌘, 的设置窗口）。登录后：文章、译文（含大模型生成）、标签、评论审核、媒体库、系统状态、Passkey、翻译模型
- 登录：RFC 8252 的浏览器授权（网站 CLAUDE.md "安全"一节）。`AppAuthRequest` 生成 PKCE verifier / state，`ASWebAuthenticationSession`（`.shared`，和 Safari 共用登录状态）打开网站的 `/admin/authorize-app`，管理员在网页上用 Passkey 登录、点"允许"，回跳 `mikexxz-blog://auth/callback?code&state`，`AdminClient.exchange` 换 token。不在 App 里直接用 Passkey：那要 Associated Domains（网站放 apple-app-site-association、App 签名带团队）
- 页面拿后台客户端一律读 `AdminSession.client`（AdminSession 在 App 根部注入）。不要在后台标签页的 NavigationStack 上另设环境值往下传：macOS 侧边栏 TabView 里推入的页面拿不到它（iPhone 上拿得到），后台页面会一直转圈（2026-10 实测）
- token 存钥匙串（`TokenStore`：数据保护钥匙串、ThisDeviceOnly；没正式签名的 Mac 构建退回文件钥匙串）。请求带 `Authorization: Bearer`；`AdminClient` 用单独的 URLSession，不存不发 cookie（API 对"只带 Bearer、不带 cookie"的请求才免 Origin 检查）、不用 URLCache。任何接口 401 → `AdminSession.handle` 清掉 token 回到登录
- 后台界面固定中文，和网页后台一样：API 的报错、状态说明都是写给管理员的中文，直接显示（`AdminAPIError.message`、字段错误 `issues`）。后台的文字用 `zh()`（`Text(verbatim:)`），不进字符串表
- 大模型翻译（`TranslationGeneration`）：段数从 `GET /admin/posts/:id/translation-plan` 拿，App 不自己切分（swift-markdown 和网站的 remark 块边界可能不同，段号会悄悄错位）。其余规则同网页：一次一个请求、开始时定下模型、失败从断点继续、只有 end_turn 算成功、未经修改才记为机器译文
- 图片上传（`ImagePreparation`，BlogKit 里，有测试）：设备上缩放到长边 ≤ 2560、重新编码去掉 EXIF / GPS、生成 640 / 1280 / 1920 版本；HEIC、WebP 转 JPEG（API 不收 HEIC，ImageIO 写不了 WebP），有透明的用 PNG，GIF / AVIF 原样。然后预签名 PUT 直传对象存储，再确认
- macOS 沙盒：`ENABLE_USER_SELECTED_FILES = readonly`（"从文件上传"）

## 渲染
- 文章语言：读者在"后台 → 设置"里选（macOS 另有 ⌘, 的设置窗口），第一次按界面语言；每篇文章还可以在工具栏里单独切换语言。界面语言跟随系统
- 时间按站点时区（Asia/Shanghai）显示和分组，和网页一致
- Markdown：swift-markdown 解析成块（`MarkdownDocument`），行内内容转成只带 Foundation 属性的 AttributedString（SwiftUI 的 Text 原生认识粗体 / 斜体 / 代码 / 删除线 / 链接）；块到视图在 `Blog/Markdown/`
- 裸网址：swift-markdown 没挂 cmark-gfm 的 autolink 扩展，`LiteralAutolinks` 移植了网站实际用的 micromark 分词器 + mdast 的正则补找两遍规则（包括"网址。"把句号算进链接的怪癖）。`BlogKitTests/Fixtures/autolinks.json` 由 `scripts/generate-autolink-fixtures.mjs` 用网站的 remark-gfm 生成（`node scripts/generate-autolink-fixtures.mjs ../mikexxz-blog > BlogKit/Tests/BlogKitTests/Fixtures/autolinks.json`），逐条对照；已知不一致见 `AutolinkFixtureTests.isKnownDifference`
- 图片：按网站的约定读 `#small` / `#medium` / `#large` / `#w=` 片段和媒体库 key，按显示宽度 × 屏幕倍率挑尺寸版本；不放大、竖图不超过视口 80%
- 正文里指向本站文章 / 标签页的链接在 App 内打开（`RoutedStack` 的 openURL），语言按读者的设置
- 中日共用汉字：文章、标题、标签按内容的语言设 `typesettingLanguage`（网页上 `lang` 的作用）

## 常用命令
- `cd BlogKit && swift test`：模型、解析、裸网址对照
- `xcodebuild -project Blog.xcodeproj -scheme Blog -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`：端到端（连线上 API）
- macOS 的 UI 测试第一次要在系统弹窗里授权自动化；签名：Team 在 Xcode 的 Signing & Capabilities 里选（已设为 KSCK2E4632）

## 测试后台
- 网站仓库 `docker compose up -d`、`bun run db:migrate`、`bun run dev`（API :8787、网站 :3000）
- 在本地开发库里给管理员建一个 session，拿到 token（库里只存 SHA-256(token)，和 `apps/api/src/auth/sessions.ts` 的 createSession 一样）
- `TEST_RUNNER_BLOG_ADMIN_TOKEN=<token> xcodebuild … -only-testing:BlogUITests/AdminUITests test`：`TEST_RUNNER_` 前缀的环境变量会传给测试进程，测试再经 `launchEnvironment` 交给 App；App 只在 Debug 构建里读 `BLOG_ADMIN_TOKEN`（`AppConfiguration.injectedAdminToken`），跳过网页登录
- 手动试网页登录：scheme 里打开 `BLOG_API_URL=http://localhost:8787`，再加 `BLOG_SITE_URL=http://localhost:3000`
