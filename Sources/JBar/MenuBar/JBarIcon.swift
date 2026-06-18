import AppKit

/// 菜单栏图标：圆圈里一个 J。返回模板图像，自动适配明/暗菜单栏。
enum JBarIcon {
    static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // 圆环
            let circleRect = rect.insetBy(dx: 1.0, dy: 1.0)
            let circle = NSBezierPath(ovalIn: circleRect)
            circle.lineWidth = 1.5
            NSColor.black.setStroke()
            circle.stroke()

            // 居中的 “J”
            let font = roundedBoldFont(ofSize: 11)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let j = NSAttributedString(string: "J", attributes: attrs)
            let textSize = j.size()
            let textRect = NSRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2 + 0.5,
                width: textSize.width,
                height: textSize.height
            )
            j.draw(in: textRect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func roundedBoldFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }
}
