import BlogKit
import Observation

/// 文章列表（首页、标签页、只按标签筛选的搜索）：游标分页，滚到底自动加载下一页。
///
/// 网站用"加载更多"按钮，因为网页上无限滚动会让页脚永远够不着、焦点难以管理；
/// 原生列表滚到底自动加载是平台惯例（App Store、邮件），页脚问题也不存在。
@Observable
final class PostFeedModel {
  struct Key: Hashable {
    let locale: ContentLocale
    let filter: PostFilter
  }

  private(set) var posts: [PostSummary] = []
  private(set) var state: Loadable<Void> = .loading
  private(set) var nextCursor: String?
  private(set) var isLoadingMore = false
  private(set) var loadMoreError: BlogAPIError?

  /// 当前列表对应的条件。条件变了（切换语言）之后才返回的旧请求直接丢弃
  @ObservationIgnored private var key: Key?

  func load(_ key: Key, client: BlogClient) async {
    self.key = key
    if posts.isEmpty { state = .loading }
    do {
      let page = try await client.posts(locale: key.locale, filter: key.filter)
      guard self.key == key else { return }
      posts = page.items
      nextCursor = page.nextCursor
      loadMoreError = nil
      state = .loaded(())
    } catch .cancelled {
      return
    } catch {
      guard self.key == key else { return }
      // 已经有内容时（下拉刷新失败）保留旧内容
      if posts.isEmpty { state = .failed(error) }
    }
  }

  func loadMore(client: BlogClient) async {
    guard let key, let cursor = nextCursor, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await client.posts(locale: key.locale, filter: key.filter, cursor: cursor)
      guard self.key == key else { return }
      // 翻页期间有新文章发布时，游标分页不会重复，但下拉刷新后的第一页可能和旧的一页重叠，去个重
      let known = Set(posts.map(\.slug))
      posts += page.items.filter { !known.contains($0.slug) }
      nextCursor = page.nextCursor
      loadMoreError = nil
    } catch .cancelled {
      return
    } catch {
      loadMoreError = error
    }
  }
}
