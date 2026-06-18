import AppKit

// 生成 JBar 应用图标各尺寸 PNG，输出到参数指定目录（默认 build/JBar.iconset）。
// 设计：圆角方形 + 蓝紫渐变 + 白色细圆环 + 居中白色 J，呼应菜单栏的“圆圈里一个 J”。

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/JBar.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func roundedHeavyFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let d = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: d, size: size) ?? base
    }
    return base
}

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.clear(canvas)

    // 圆角方形（留边给阴影/呼吸感）
    let margin = size * 0.085
    let rect = canvas.insetBy(dx: margin, dy: margin)
    let radius = rect.width * 0.2237   // macOS 连续圆角近似比例
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 渐变填充
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    // 即刻品牌黄 #FFE411，配一点点深浅做出层次
    let colors = [
        NSColor(srgbRed: 1.00, green: 0.925, blue: 0.20, alpha: 1).cgColor,  // 略亮
        NSColor(srgbRed: 1.00, green: 0.894, blue: 0.067, alpha: 1).cgColor, // #FFE411
    ]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    // 白色细圆环
    let ringInset = rect.width * 0.165
    let ringRect = rect.insetBy(dx: ringInset, dy: ringInset)
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.88).cgColor)
    ctx.setLineWidth(max(1, size * 0.030))
    ctx.strokeEllipse(in: ringRect)

    // 居中 “J”（黑色，呼应即刻黄+黑配色）
    let fontSize = rect.width * 0.40
    let attrs: [NSAttributedString.Key: Any] = [
        .font: roundedHeavyFont(fontSize),
        .foregroundColor: NSColor.black,
    ]
    let s = NSAttributedString(string: "J", attributes: attrs)
    let ts = s.size()
    s.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2 + size * 0.01))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconset 需要的尺寸与命名
let specs: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for spec in specs {
    let data = render(spec.px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(spec.name)"))
}
print("已生成 \(specs.count) 个尺寸 -> \(outDir)")
