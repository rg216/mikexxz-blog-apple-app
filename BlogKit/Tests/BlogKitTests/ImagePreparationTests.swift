import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import BlogKit

struct ImagePreparationTests {
  /// 合成一张带 GPS 和相机信息的照片
  func photo(width: Int, height: Int, type: UTType = .jpeg, alpha: Bool = false) throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: alpha ? 0.5 : 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
    let metadata: [CFString: Any] = [
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.68, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 139.76, kCGImagePropertyGPSLongitudeRef: "E"],
      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "iPhone"],
    ]
    CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

  func properties(_ data: Data) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }

  @Test func shrinksToTheMaximumLongEdgeAndStripsLocation() throws {
    let input = try photo(width: 4000, height: 3000)
    #expect(try properties(input)[kCGImagePropertyGPSDictionary] != nil)

    let prepared = try ImagePreparation.prepare(input, filename: "IMG_0001.HEIC")
    #expect(prepared.contentType == "image/jpeg")
    #expect(prepared.filename == "IMG_0001.jpg")
    #expect(prepared.width == 2560)
    #expect(prepared.height == 1920)
    let output = try properties(prepared.data)
    #expect(output[kCGImagePropertyGPSDictionary] == nil)
    #expect((output[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
  }

  @Test func generatesOnlyNarrowerVariants() throws {
    let big = try ImagePreparation.prepare(try photo(width: 4000, height: 3000), filename: "a.jpg")
    #expect(big.variants.keys.sorted() == [640, 1280, 1920])
    #expect(try properties(try #require(big.variants[640]))[kCGImagePropertyPixelWidth] as? Int == 640)
    #expect(try properties(try #require(big.variants[640]))[kCGImagePropertyPixelHeight] as? Int == 480)

    let small = try ImagePreparation.prepare(try photo(width: 1000, height: 800), filename: "b.jpg")
    #expect(small.width == 1000)
    #expect(small.variants.keys.sorted() == [640])
  }

  @Test func keepsPNGForTransparentImages() throws {
    let prepared = try ImagePreparation.prepare(try photo(width: 300, height: 200, type: .png, alpha: true), filename: "logo.png")
    #expect(prepared.contentType == "image/png")
    #expect(prepared.filename == "logo.png")
  }

  @Test func uploadsGIFsUntouched() throws {
    let gif = try photo(width: 50, height: 40, type: .gif)
    let prepared = try ImagePreparation.prepare(gif, filename: "anim.gif")
    #expect(prepared.data == gif)
    #expect(prepared.contentType == "image/gif")
    #expect(prepared.variants.isEmpty)
    #expect(prepared.width == 50)
  }

  @Test func rejectsWhatIsNotAnImage() {
    #expect(throws: ImagePreparation.Failure.unreadable) { try ImagePreparation.prepare(Data("not an image".utf8), filename: "x.txt") }
  }
}
