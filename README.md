# mikexxz for iPhone, iPad and Mac

A native SwiftUI reader for the [mikexxz blog](https://mikexzx-blog.vercel.app): posts, tags, archive, full-text search and comments (read-only), in Chinese, English and Japanese.

- One multiplatform target (iOS, iPadOS and native macOS), Xcode 27, iOS / macOS 27.0
- `BlogKit` — a local Swift package with the API client, models and Markdown parsing; `cd BlogKit && xcrun swift test`
- Talks to the public, read-only API at `https://mikexzx-blog-api.vercel.app`

Open `Blog.xcodeproj`, pick your team under *Signing & Capabilities*, and run.
