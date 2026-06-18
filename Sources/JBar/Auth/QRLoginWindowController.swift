import AppKit

/// 扫码登录窗口：展示二维码 + 状态文案。
@MainActor
final class QRLoginWindowController {
    var onCancel: (() -> Void)?

    private let window: NSWindow
    private let qrImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "扫码登录即刻")

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "JBar 登录"
        window.isReleasedWhenClosed = false
        window.center()
        buildUI()
    }

    private func buildUI() {
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center

        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        qrImageView.layer?.cornerRadius = 8

        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [titleLabel, qrImageView, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            qrImageView.widthAnchor.constraint(equalToConstant: 220),
            qrImageView.heightAnchor.constraint(equalToConstant: 220),
            stack.widthAnchor.constraint(equalToConstant: 280),
        ])

        window.contentView = content
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(status: String, qr: NSImage?) {
        statusLabel.stringValue = status
        if let qr { qrImageView.image = qr }
    }

    func close() {
        window.orderOut(nil)
    }
}
