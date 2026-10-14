import BlogKit
import SwiftUI

/// 系统状态：各项依赖配好了没有、能不能用，定时任务最近一次的结果。只报告状态，不返回任何配置值。
/// 不自动刷新：每次检查都会连各个服务（包括 Anthropic）
struct SystemStatusView: View {
  private var client: AdminClient? { session.client }
  @Environment(AdminSession.self) private var session
  @State private var status: SystemStatus?
  @State private var error: AdminAPIError?
  @State private var checking = false

  var body: some View {
    List {
      if let error {
        AdminErrorBanner(error: error) { Task { await check() } }
      }
      if let status {
        Section {
          let overall = StatusState.worst(status.checks.map(\.state) + status.jobs.map(\.state))
          Label { zh(overall.summary) } icon: { overall.icon }
            .font(.app(.headline))
          LabeledContent { zh(status.checkedAt.adminFormatted) } label: { zh("检查于") }
            .rowFont()
          LabeledContent { zh(status.version.map { String($0.prefix(7)) } ?? "本地") } label: { zh("API 版本") }
            .rowFont()
        }
        Section {
          ForEach(status.checks) { check in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              check.state.icon
              VStack(alignment: .leading, spacing: 2) {
                zh(Self.checkName(check.id)).font(.app(.subheadline).weight(.semibold))
                zh(check.summary).font(.app(.footnote)).foregroundStyle(.secondary)
              }
              Spacer()
              if let latency = check.latencyMs {
                zh("\(Int(latency.rounded())) ms").font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          zh("依赖")
        }
        Section {
          ForEach(status.jobs) { job in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              job.state.icon
              VStack(alignment: .leading, spacing: 2) {
                zh(Self.jobName(job.name)).font(.app(.subheadline).weight(.semibold))
                zh(job.lastSuccessAt.map { "最近一次成功：\($0.adminFormatted)" } ?? "从未运行")
                  .font(.app(.footnote)).foregroundStyle(.secondary)
                if let lastRun = job.lastRunAt, lastRun != job.lastSuccessAt, let detail = job.detail {
                  zh("最近一次（\(lastRun.adminFormatted)）失败：\(detail)").font(.app(.footnote)).foregroundStyle(.red)
                }
              }
            }
          }
        } header: {
          zh("定时任务")
        } footer: {
          zh("每天运行一次，超过 26 小时没有成功会提示注意。")
        }
      } else if error == nil {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(zh("系统状态"))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await check() }
        } label: {
          Label { zh("重新检查") } icon: { Image(systemName: "arrow.clockwise") }
        }
        .disabled(checking)
      }
    }
    .task { await check() }
  }

  private func check() async {
    guard let client else { return }
    checking = true
    defer { checking = false }
    do {
      status = try await client.status()
      error = nil
    } catch where error.kind == .cancelled {
      return
    } catch {
      session.handle(error)
      self.error = error
    }
  }

  static func checkName(_ id: String) -> String {
    switch id {
    case "database": "数据库"
    case "migrations": "数据库迁移"
    case "redis": "Redis（限流、阅读数）"
    case "storage": "图片存储"
    case "anthropic": "Claude API"
    case "github": "GitHub 登录（评论）"
    case "revalidate": "缓存失效通知"
    case "cron": "定时任务密钥"
    default: id
    }
  }

  static func jobName(_ name: String) -> String {
    switch name {
    case "views-flush": "写入阅读数（每天 00:10）"
    case "images-cleanup": "清理未确认的图片（每天 00:20）"
    default: name
    }
  }
}

extension StatusState {
  var summary: String {
    switch self {
    case .ok: "一切正常"
    case .warning: "有需要注意的地方"
    case .error: "有服务出错了"
    case .off: "可选功能未配置"
    }
  }

  @ViewBuilder var icon: some View {
    switch self {
    case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
    case .off: Image(systemName: "minus.circle").foregroundStyle(.secondary)
    }
  }
}
