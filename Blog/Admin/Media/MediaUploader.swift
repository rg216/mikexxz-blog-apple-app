import BlogKit
import Foundation
import Observation

/// 上传一批图片：设备上处理（缩放、去 EXIF、生成版本）→ API 签发上传地址 → 直接 PUT 到对象存储 → 确认。
/// 文件不经过 API（Vercel 函数的请求体上限 4.5MB），API 只签名和核对
@Observable
final class MediaUploader {
  struct Item: Sendable {
    let data: Data
    let filename: String
  }

  private(set) var total = 0
  private(set) var done = 0
  private(set) var failures: [String] = []

  var isUploading: Bool { done < total }

  func upload(_ items: [Item], folderId: Int?, client: AdminClient) async -> [AdminImage] {
    total = items.count
    done = 0
    failures = []
    var uploaded: [AdminImage] = []
    for item in items {
      defer { done += 1 }
      do {
        uploaded.append(try await upload(item, folderId: folderId, client: client))
      } catch let error as ImagePreparation.Failure {
        failures.append("\(item.filename)：\(error.message)")
      } catch let error as AdminAPIError {
        failures.append("\(item.filename)：\(error.message)")
      } catch {
        failures.append("\(item.filename)：\(error.localizedDescription)")
      }
    }
    return uploaded
  }

  private func upload(_ item: Item, folderId: Int?, client: AdminClient) async throws -> AdminImage {
    let prepared = try await Self.prepare(item)
    let request = ImageUploadRequest(
      contentType: prepared.contentType, size: prepared.data.count, filename: prepared.filename,
      variants: prepared.variants.keys.sorted().map { ImageUploadRequest.Variant(width: $0, size: prepared.variants[$0]!.count) }, folderId: folderId)
    let upload = try await client.requestUpload(request)
    try await client.upload(prepared.data, to: upload.upload)
    for target in upload.variants {
      guard let width = target.width, let data = prepared.variants[width] else { continue }
      try await client.upload(data, to: target)
    }
    return try await client.confirmImage(id: upload.image.id)
  }

  /// 解码、缩放、编码比较费时，放到主线程之外
  @concurrent private static func prepare(_ item: Item) async throws -> ImagePreparation.Prepared {
    try ImagePreparation.prepare(item.data, filename: item.filename)
  }
}
