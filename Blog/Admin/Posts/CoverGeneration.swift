import BlogKit
import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI

/// 生成头图（网页编辑器的 CoverGenerator）：两步都由作者点按钮触发，都可以停止。
///   1. 画面描述：让 Claude 按文章写（可以先给个方向），或者自己写；描述可以随便改
///   2. 出图：按设置里的模型、画质和头图风格出一张 16:9 的图，生成中显示预览。可以连出几张，挑一张"设为头图"
/// 选中的那张这时才上传进媒体库（MediaUploader：和手动上传同一条路），没选的不进存储。
///
/// 状态放在这个对象里、由文章编辑页持有，而不是放在弹出的 sheet 里：关掉 sheet 再打开，已经生成的图还在（和网页一样）；
/// 离开编辑页时编辑页调 `cancel()`，正在进行的请求随之中止，不再计费
@Observable
final class CoverGeneration {
  enum Phase: Equatable {
    case idle
    case running
    case failed(String)
  }

  struct Candidate: Identifiable {
    /// 第几张（从 1 起）
    let n: Int
    let image: CoverImage
    let preview: Image?
    var id: Int { n }
  }

  /// 文章表单里此刻的内容（新文章还没保存也能生成）
  struct Source {
    let title: String
    let slug: String
    /// 标签的名称
    let tags: [String]
    let content: String
  }

  private(set) var config: CoverConfig?
  private(set) var configError: AdminAPIError?

  var direction = ""
  var prompt = ""
  var alt = ""

  private(set) var brief = Phase.idle
  private(set) var image = Phase.idle
  /// 出图开始的时间：一张图可能要一两分钟，界面显示已用时间，免得看起来像卡住了
  private(set) var imageStartedAt: Date?
  /// 生成中的预览（partial）
  private(set) var preview: Image?
  private(set) var candidates: [Candidate] = []
  var selected: Int?

  private(set) var uploading = false
  private(set) var uploadError: String?

  private var briefTask: Task<Void, Never>?
  private var imageTask: Task<Void, Never>?

  /// 每次打开都重读：设置可能刚改过
  func loadConfig(client: AdminClient) async {
    do {
      config = try await client.coverConfig()
      configError = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      configError = error
    }
  }

  /// 写描述；正在写时再按一次就是停止
  func toggleBrief(client: AdminClient, source: Source, onError: @escaping (AdminAPIError) -> Void) {
    if brief == .running {
      briefTask?.cancel()
      return
    }
    brief = .running
    let input = CoverBriefInput(title: source.title, tags: source.tags, contentMd: source.content, direction: direction)
    briefTask = Task {
      do throws(AdminAPIError) {
        let result = try await client.writeCoverBrief(input)
        prompt = result.prompt
        alt = result.alt
        brief = .idle
      } catch where error.kind == .cancelled {
        brief = .idle
      } catch {
        onError(error)
        brief = .failed(error.message)
      }
    }
  }

  /// 出图；正在出图时再按一次就是停止
  func toggleImage(client: AdminClient, onError: @escaping (AdminAPIError) -> Void) {
    if image == .running {
      imageTask?.cancel()
      return
    }
    image = .running
    imageStartedAt = .now
    preview = nil
    let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    imageTask = Task {
      defer {
        imageStartedAt = nil
        preview = nil
      }
      do {
        var result: CoverImage?
        for try await event in try await client.generateCoverImage(prompt: prompt) {
          switch event {
          case .ping, .unknown:
            break
          case .partial(_, _, let data):
            preview = Self.decode(data)
          case .done(let done):
            result = done
          case .error(_, let message):
            image = .failed(message)
            return
          }
        }
        // 流正常结束却没有 done：连接中途断了
        guard let result else {
          image = Task.isCancelled ? .idle : .failed("连接中断，图片没有生成完，请重试")
          return
        }
        let n = (candidates.last?.n ?? 0) + 1
        candidates.append(Candidate(n: n, image: result, preview: Self.decode(result.data)))
        selected = n
        image = .idle
      } catch let error as AdminAPIError {
        if error.kind == .cancelled {
          image = .idle
        } else {
          onError(error)
          image = .failed(error.message)
        }
      } catch {
        // 取消 Task 时 bytes.lines 抛 CancellationError / URLError.cancelled
        image = Task.isCancelled ? .idle : .failed("连接中断：\(error.localizedDescription)")
      }
    }
  }

  /// 把选中的那张上传进媒体库，写上图片描述。成功时返回媒体库里的图片
  func uploadSelected(client: AdminClient, slug: String, onError: (AdminAPIError) -> Void) async -> AdminImage? {
    guard let candidate = candidates.first(where: { $0.n == selected }), !uploading else { return nil }
    uploading = true
    uploadError = nil
    defer { uploading = false }
    let uploader = MediaUploader()
    let filename = CoverOptions.fileName(slug: slug, n: candidate.n, contentType: candidate.image.contentType)
    guard var uploaded = await uploader.upload([.init(data: candidate.image.data, filename: filename)], folderId: nil, client: client).first else {
      uploadError = uploader.failures.first ?? "上传失败"
      return nil
    }
    let description = String(alt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CoverOptions.altMaxLength))
    if !description.isEmpty {
      do {
        uploaded = try await client.updateImage(id: uploaded.id, ImageUpdateInput(description: description))
      } catch {
        // 图已经进了媒体库，只是没写上描述：照样设为头图，提示去媒体库补上
        onError(error)
        uploadError = "图片已上传，但图片描述没有保存（\(error.message)）：可以在媒体库里补上。"
      }
    }
    return uploaded
  }

  func cancel() {
    briefTask?.cancel()
    imageTask?.cancel()
  }

  /// base64 解出来的图片 → SwiftUI 的 Image（预览用；WebP、PNG、JPEG 都由 ImageIO 解码）
  private static func decode(_ data: Data) -> Image? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return Image(decorative: image, scale: 1)
  }
}
