import BlogKit
import Foundation
import Observation

/// 用大模型生成一篇译文：先标题，再逐段生成正文（段数由服务器按它的切分规则给出）。
///
/// 和网页编辑器同样的约束：
/// - 一次只发一个请求：各请求共享"整篇原文"的提示缓存前缀，并行会全部错过缓存
/// - 模型在开始时定下，标题和每一段都带同一个（提示缓存按模型分开，中途改了设置也不换）
/// - 失败后重试从失败的那一段继续（同一版原文），已经生成的不重来
/// - 只有 stopReason = end_turn 算成功：拒答、截断都是失败
@Observable
final class TranslationGeneration {
  enum Phase: Equatable {
    case idle
    case running
    case failed(String)
    case finished
  }

  private(set) var phase = Phase.idle
  /// 0 是标题，1… 是正文的段
  private(set) var step = 0
  private(set) var totalSteps = 0
  /// 当前这一段已经流过来的文字（实时显示）
  private(set) var streaming = ""
  /// 当前这一段还没有任何文字、但收到了心跳：模型在思考
  private(set) var thinking = false
  private(set) var usage = TranslationUsage.zero

  private(set) var title: String?
  private(set) var segments: [String] = []
  private var models: [String] = []
  /// 这次生成依据的原文；换了原文就不能接着上次失败的地方继续
  private var sourceHash: String?
  private var model: String?

  var combinedModel: String { ModelNames.combine(models) }
  var body: String { segments.joined() }

  /// 失败之后能不能从断点继续
  var canResume: Bool {
    if case .failed = phase { return sourceHash != nil } else { return false }
  }

  func reset() {
    phase = .idle
    title = nil
    segments = []
    models = []
    usage = .zero
    sourceHash = nil
    model = nil
    streaming = ""
    step = 0
    totalSteps = 0
  }

  /// 从头开始，或者（resume）从上次失败的地方继续
  func run(client: AdminClient, post: AdminPost, locale: ContentLocale, model startModel: String, resume: Bool) async {
    if !resume || sourceHash != post.sourceHash {
      reset()
      sourceHash = post.sourceHash
      model = startModel
    }
    guard let model else { return }
    phase = .running
    do {
      let plan = try await client.translationPlan(postId: post.id)
      guard plan.sourceHash == post.sourceHash else {
        phase = .failed("原文已更新，请先载入最新原文再生成。")
        sourceHash = nil
        return
      }
      totalSteps = plan.segments + 1

      if title == nil {
        step = 0
        let result = try await client.generateTitle(postId: post.id, locale: locale, sourceHash: post.sourceHash, model: model)
        title = result.title
        models.append(result.model)
        usage = usage + result.usage
      }

      while segments.count < plan.segments {
        try Task.checkCancellation()
        step = segments.count + 1
        streaming = ""
        thinking = false
        let stream = try await client.generateSegment(postId: post.id, locale: locale, index: segments.count, sourceHash: post.sourceHash, model: model)
        var finished = false
        for try await event in stream {
          switch event {
          case .ping:
            if streaming.isEmpty { thinking = true }
          case .delta(let text):
            thinking = false
            streaming += text
          case .done(let text, let stopReason, let servedModel, let segmentUsage):
            usage = usage + segmentUsage
            models.append(servedModel)
            guard stopReason == "end_turn" else { throw GenerationFailure(Self.stopMessage(stopReason)) }
            // 服务器已经按原文段对齐了首尾空行（fitTranslatedSegment），直接拼接
            segments.append(text)
            finished = true
          case .error(_, let message):
            throw GenerationFailure(message)
          case .unknown:
            break
          }
        }
        // 只有心跳、没有 done 的流：连接中途断了
        guard finished else { throw GenerationFailure("连接中断，第 \(segments.count + 1) 段没有生成完") }
      }
      streaming = ""
      thinking = false
      phase = .finished
    } catch is CancellationError {
      phase = .failed("已停止。")
    } catch let error as AdminAPIError where error.kind == .cancelled {
      phase = .failed("已停止。")
    } catch let error as AdminAPIError {
      if error.isConflict { sourceHash = nil }
      phase = .failed(error.message)
    } catch let error as GenerationFailure {
      phase = .failed(error.message)
    } catch {
      phase = .failed("生成失败：\(error.localizedDescription)")
    }
  }

  struct GenerationFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
  }

  static func stopMessage(_ stopReason: String) -> String {
    switch stopReason {
    case "refusal": "模型拒绝翻译这一段。"
    case "max_tokens": "这一段的译文超出了输出上限，被截断了。"
    default: "模型没有正常结束（\(stopReason)）。"
    }
  }
}
