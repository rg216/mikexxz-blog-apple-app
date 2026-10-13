// 生成 App 图标（1024×1024，不带圆角：系统会套上自己的形状）。
// 不能用 SF Symbols 或 SF 字体做图标（许可证不允许用在 App 图标 / logo 上），所以用几何图形画一页纸。
// 用法：xcrun swift scripts/make-app-icon.swift Blog/Resources/Assets.xcassets/AppIcon.appiconset
// 之后 macOS 的各个尺寸：在该目录里 for s in 16 32 128 256 512; do sips -z $s $s AppIcon.png --out mac-$s.png; sips -z $((s*2)) $((s*2)) AppIcon.png --out mac-$s@2x.png; done
import AppKit
import CoreGraphics

let size = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func render(dark: Bool) -> Data {
  let space = CGColorSpace(name: CGColorSpace.displayP3)!
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let s = CGFloat(size)

  // 背景：系统蓝的竖向渐变（浅色 #0A84FF → #0060DF；深色模式下是近黑底，纸页保留蓝色）
  let colors = dark
    ? [CGColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1), CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)]
    : [CGColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1), CGColor(srgbRed: 0.0, green: 0.38, blue: 0.87, alpha: 1)]
  let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
  context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

  // 一页纸：圆角矩形 + 一行粗标题 + 三行正文
  let page = CGRect(x: s * 0.25, y: s * 0.19, width: s * 0.5, height: s * 0.62)
  context.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.04, color: CGColor(gray: 0, alpha: 0.25))
  context.setFillColor(dark ? CGColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1) : CGColor(gray: 1, alpha: 1))
  context.addPath(CGPath(roundedRect: page, cornerWidth: s * 0.06, cornerHeight: s * 0.06, transform: nil))
  context.fillPath()
  context.setShadow(offset: .zero, blur: 0, color: nil)

  let ink = dark ? CGColor(gray: 1, alpha: 0.95) : CGColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
  let faint = dark ? CGColor(gray: 1, alpha: 0.55) : CGColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.35)
  let left = page.minX + s * 0.07
  let lineHeight = s * 0.045
  func bar(y: CGFloat, width: CGFloat, height: CGFloat, color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: CGRect(x: left, y: y, width: width, height: height), cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
    context.fillPath()
  }
  bar(y: page.maxY - s * 0.15, width: page.width * 0.62, height: lineHeight * 1.5, color: ink)
  for (index, fraction) in [0.72, 0.72, 0.5].enumerated() {
    bar(y: page.maxY - s * 0.27 - CGFloat(index) * s * 0.1, width: page.width * fraction, height: lineHeight, color: faint)
  }

  let image = context.makeImage()!
  return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

try render(dark: false).write(to: output.appending(component: "AppIcon.png"))
try render(dark: true).write(to: output.appending(component: "AppIcon-Dark.png"))
