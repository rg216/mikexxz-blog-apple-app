import BlogKit
import SwiftUI

/// 生成头图的 sheet（流程见 CoverGeneration）。关掉不会丢掉已经生成的图，也不会停止正在进行的生成
struct CoverGeneratorView: View {
  let generation: CoverGeneration
  let source: CoverGeneration.Source
  /// 选中的图已进媒体库：设为头图
  let onPick: (AdminImage) -> Void

  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var generation = generation
    NavigationStack {
      Form {
        if let config = generation.config {
          briefSection(config.brief)
          Section {
            TextEditor(text: $generation.prompt)
              .font(.app(.body))
              .frame(minHeight: 140)
              .disabled(generation.brief == .running)
              .accessibilityLabel(zh("画面描述"))
              .accessibilityIdentifier("cover-prompt")
          } header: {
            zh("画面描述")
          } footer: {
            zh("英文，和设置里的“头图风格”一起发给图像模型。可以直接改，或者自己写。\(generation.prompt.count) / \(CoverOptions.promptMaxLength) 字")
              .foregroundStyle(generation.prompt.count > CoverOptions.promptMaxLength ? .red : .secondary)
              .footerFont()
          }
          Section {
            TextField(text: $generation.alt, axis: .vertical) { zh("图片描述") }
              .rowFont()
              .accessibilityIdentifier("cover-alt")
          } header: {
            zh("图片描述")
          } footer: {
            zh("读屏软件读给看不见图片的读者：写进媒体库，所有用到这张图的地方共用。").footerFont()
          }
          imageSection(config.image)
          if !generation.candidates.isEmpty {
            candidatesSection
          }
        } else if let error = generation.configError {
          AdminErrorBanner(error: error) { Task { await loadConfig() } }
        } else {
          ProgressView().frame(maxWidth: .infinity)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(zh("生成头图"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { zh("关闭") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await pick() }
          } label: {
            zh(generation.uploading ? "正在上传…" : "设为头图")
          }
          .disabled(generation.selected == nil || generation.uploading)
        }
      }
      .task { await loadConfig() }
    }
    #if os(macOS)
      .frame(minWidth: 560, idealWidth: 640, minHeight: 640, idealHeight: 760)
    #endif
  }

  // MARK: - 第一步：画面描述

  private func briefSection(_ step: CoverConfig.Step) -> some View {
    @Bindable var generation = generation
    let model = TranslationModelInfo.name(of: step.model)
    let running = generation.brief == .running
    let noTitle = source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return Section {
      TextField(text: $generation.direction, axis: .vertical) { zh("方向（可选）") }
        .rowFont()
        .accessibilityIdentifier("cover-direction")
      Button {
        guard let client else { return }
        generation.toggleBrief(client: client, source: source, onError: session.handle)
      } label: {
        Label {
          zh(running ? "停止" : "用 \(model) 写描述")
        } icon: {
          Image(systemName: running ? "stop.fill" : "sparkles")
        }
      }
      .disabled(!step.available || (!running && noTitle))
      .rowFont()
      if running {
        Label { zh("\(model) 正在读文章…") } icon: { ProgressView().controlSize(.small) }
          .font(.app(.footnote))
          .foregroundStyle(.secondary)
      }
      if case .failed(let message) = generation.brief {
        AdminErrorBanner(error: AdminAPIError(kind: .server, message: "没有写成：\(message)"))
      }
    } header: {
      zh("1. 画面描述")
    } footer: {
      Group {
        if !step.available {
          zh(Self.briefUnavailableNote(step.reason))
        } else if noTitle {
          zh("先写标题。")
        } else {
          zh("比如“用钥匙比喻缓存”“暖色调”；不写就让 Claude 自己想。Claude 读标题、标签和正文的前 1.2 万字。")
        }
      }
      .footerFont()
    }
  }

  // MARK: - 第二步：图片

  private func imageSection(_ step: CoverConfig.Step) -> some View {
    let running = generation.image == .running
    let noPrompt = generation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let tooLong = generation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count > CoverOptions.promptMaxLength
    return Section {
      Button {
        guard let client else { return }
        generation.toggleImage(client: client, onError: session.handle)
      } label: {
        Label {
          zh(running ? "停止" : generation.candidates.isEmpty ? "用 \(CoverOptions.imageModelName(step.model)) 生成" : "再生成一张")
        } icon: {
          Image(systemName: running ? "stop.fill" : "photo")
        }
      }
      .disabled(!step.available || (!running && (noPrompt || tooLong)))
      .rowFont()
      .accessibilityIdentifier("cover-generate")
      if running {
        VStack(alignment: .leading, spacing: 8) {
          Group {
            if let preview = generation.preview {
              preview.resizable().scaledToFit()
            } else {
              Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
            }
          }
          .clipShape(.rect(cornerRadius: 8, style: .continuous))
          .accessibilityHidden(true)
          TimelineView(.periodic(from: generation.imageStartedAt ?? .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(generation.imageStartedAt ?? context.date))
            Label {
              zh("正在生成\(generation.preview == nil ? "" : "（预览）")… 已用 \(max(seconds, 0)) 秒，通常要半分钟到两分钟")
            } icon: {
              ProgressView().controlSize(.small)
            }
            .font(.app(.footnote))
            .foregroundStyle(.secondary)
          }
        }
      }
      if case .failed(let message) = generation.image {
        AdminErrorBanner(error: AdminAPIError(kind: .server, message: "没有生成：\(message)"))
      }
    } header: {
      zh("2. 图片")
    } footer: {
      Group {
        if !step.available {
          zh(Self.imageUnavailableNote(step.reason))
        } else {
          zh("画质：\(CoverOptions.qualityName(step.quality ?? ""))（在“设置”里改）。")
        }
      }
      .footerFont()
    }
  }

  private var candidatesSection: some View {
    Section {
      if let error = generation.uploadError {
        AdminErrorBanner(error: AdminAPIError(kind: .server, message: error))
      }
      ForEach(generation.candidates.reversed()) { candidate in
        Button {
          generation.selected = candidate.n
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Group {
              if let preview = candidate.preview {
                preview.resizable().scaledToFit()
              } else {
                Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
              }
            }
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
              if generation.selected == candidate.n {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.tint, lineWidth: 3)
              }
            }
            HStack {
              zh("第 \(candidate.n) 张 · \(CoverOptions.qualityName(candidate.image.quality)) · 输入 \(candidate.image.usage.inputTokens.formatted()) · 输出 \(candidate.image.usage.outputTokens.formatted()) token")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
              Spacer()
              if generation.selected == candidate.n {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
              }
            }
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(zh("第 \(candidate.n) 张"))
        .accessibilityAddTraits(generation.selected == candidate.n ? .isSelected : [])
        .accessibilityIdentifier("cover-candidate")
      }
    } header: {
      zh("选一张作为头图")
    } footer: {
      zh("选中的那张在“设为头图”时才上传进媒体库，没选的不保存。").footerFont()
    }
  }

  // MARK: -

  private func loadConfig() async {
    guard let client else { return }
    await generation.loadConfig(client: client)
    if let error = generation.configError { session.handle(error) }
  }

  private func pick() async {
    guard let client else { return }
    guard let image = await generation.uploadSelected(client: client, slug: source.slug, onError: session.handle) else { return }
    onPick(image)
    session.dataChanged()
    // 图片描述没保存上时留在这里显示提示
    if generation.uploadError == nil { dismiss() }
  }

  static func briefUnavailableNote(_ reason: String?) -> String {
    switch reason {
    case "rate_limiter_unavailable": "限流服务（Redis）暂时连不上：为了控制费用，先停用，请稍后重试。"
    default: "服务器没有启用 Claude（需要 ANTHROPIC_API_KEY 和 REDIS_URL），可以自己写画面描述。"
    }
  }

  static func imageUnavailableNote(_ reason: String?) -> String {
    switch reason {
    case "rate_limiter_unavailable": "限流服务（Redis）暂时连不上：为了控制费用，出图先停用，请稍后重试。"
    default: "服务器没有启用出图（需要 OPENAI_API_KEY 和 REDIS_URL）。"
    }
  }
}
