import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 上传前在设备上处理图片（和网站后台在浏览器里做的一样，见网站 CLAUDE.md "媒体库与图片"）：
/// - 缩放到长边 ≤ 2560，重新编码；重新编码不写任何元数据，照片里的 EXIF（含 GPS 位置）就去掉了
/// - 生成比原图窄的 640 / 1280 / 1920 宽的版本
/// - GIF（可能是动图）、AVIF 原样上传、不生成版本
///
/// 格式：JPEG 仍是 JPEG；PNG、有透明通道的图片用 PNG；HEIC（iPhone 拍的照片）和 WebP 变成 JPEG——
/// API 不收 HEIC，ImageIO 也写不了 WebP
public enum ImagePreparation {
  public static let maxLongEdge = 2560
  public static let variantWidths = [640, 1280, 1920]
  /// 与网站的 MAX_IMAGE_BYTES 一致
  public static let maxBytes = 10 * 1024 * 1024
  static let jpegQuality = 0.85

  public struct Prepared: Sendable {
    public let contentType: String
    public let data: Data
    public let filename: String
    public let width: Int
    public let height: Int
    /// 宽度 → 文件
    public let variants: [Int: Data]
  }

  public enum Failure: Error, Equatable, Sendable {
    case unreadable
    case tooLarge
    case encodingFailed

    public var message: String {
      switch self {
      case .unreadable: "读不出这张图片（只支持 JPEG、PNG、HEIC、WebP、AVIF、GIF）"
      case .tooLarge: "图片不能超过 10MB"
      case .encodingFailed: "图片重新编码失败"
      }
    }
  }

  public static func prepare(_ data: Data, filename: String) throws(Failure) -> Prepared {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source).map({ UTType($0 as String) }) ?? nil
    else { throw .unreadable }
    let base = (filename as NSString).deletingPathExtension.isEmpty ? "image" : (filename as NSString).deletingPathExtension

    // 动图和 AVIF 原样上传
    if type.conforms(to: .gif) || type.identifier == "public.avif" {
      guard data.count <= maxBytes else { throw .tooLarge }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
      let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
      let isGIF = type.conforms(to: .gif)
      return Prepared(
        contentType: isGIF ? "image/gif" : "image/avif", data: data, filename: base + (isGIF ? ".gif" : ".avif"), width: width, height: height, variants: [:])
    }

    // 缩略图接口顺带按 EXIF 方向转正，按长边缩放；Always：忽略文件里内嵌的小缩略图，从原图生成
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw .unreadable }

    let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    let usePNG = type.conforms(to: .png) || (hasAlpha && !type.conforms(to: .jpeg))
    let outputType: UTType = usePNG ? .png : .jpeg

    let original = try encode(image, as: outputType)
    guard original.count <= maxBytes else { throw .tooLarge }

    var variants: [Int: Data] = [:]
    for width in variantWidths where width < image.width {
      let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
      guard let scaled = resize(image, width: width, height: height) else { throw .encodingFailed }
      variants[width] = try encode(scaled, as: outputType)
    }

    return Prepared(
      contentType: usePNG ? "image/png" : "image/jpeg", data: original, filename: base + (usePNG ? ".png" : ".jpg"),
      width: image.width, height: image.height, variants: variants)
  }

  /// 只写像素，不写任何属性（EXIF、GPS、相机信息都不带）
  static func encode(_ image: CGImage, as type: UTType) throws(Failure) -> Data {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { throw .encodingFailed }
    let properties: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
    return output as Data
  }

  static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
