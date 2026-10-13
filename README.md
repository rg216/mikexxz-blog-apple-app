# mikexxz for iPhone, iPad and Mac

A native SwiftUI app for the [mikexxz blog](https://mikexzx-blog.vercel.app).

- **Reading:** posts, tags, archive, full-text search and comments (read-only), in Chinese, English and Japanese
- **Admin** (the 后台 tab): posts and translations (including Claude-generated ones), tags, comment moderation, the media library with on-device image processing, system status, Passkeys and the reader's article language. Sign in through the website with your Passkey; the app keeps a bearer session in the Keychain

Project layout:

- One multiplatform target (iOS, iPadOS and native macOS), Xcode 27, iOS / macOS 27.0
- `BlogKit` — a local Swift package with the API clients, models, Markdown parsing and image preparation; `cd BlogKit && swift test`
- Talks to the API at `https://mikexzx-blog-api.vercel.app` (set `BLOG_API_URL` / `BLOG_SITE_URL` in the scheme for local development)

Open `Blog.xcodeproj` and run. See `CLAUDE.md` for the design decisions.
