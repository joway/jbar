import AppKit
import SwiftUI

/// 刘海风格通知：从屏幕顶部（贴刘海）向下"生长"展开一张卡片。
/// 多条新动态逐条排队（FIFO）依次弹出。点击打开网页版。
@MainActor
final class NotchNotifier {
    private let width: CGFloat = 380
    private let fullHeight: CGFloat = 100
    private let displayDuration: TimeInterval = 5
    private let gapBetween: TimeInterval = 0.4

    private var panel: NSPanel?
    private var container: NSView?
    private var queue: [FeedPost] = []
    private var isShowing = false
    private var dismissWork: DispatchWorkItem?

    // MARK: - 对外接口

    func enqueue(_ post: FeedPost) {
        jlog("enqueue 通知：\(post.authorName)")
        queue.append(post)
        showNextIfIdle()
    }

    /// 用于预览弹窗效果的测试通知。
    func enqueueTest() {
        let post = FeedPost(
            id: "6a3385121cb24c1579091a97",
            type: "ORIGINAL_POST",
            content: "这是一条测试动态，用来预览刘海通知的弹出效果 ✨ 点我会在浏览器打开网页版。",
            authorName: "JBar 测试",
            authorAvatarURL: nil,
            createdAt: Date()
        )
        enqueue(post)
    }

    // MARK: - 队列调度

    private func showNextIfIdle() {
        guard !isShowing, !queue.isEmpty else { return }
        let post = queue.removeFirst()
        present(post)
    }

    // MARK: - 几何

    private struct Geometry {
        let collapsed: NSRect
        let expanded: NSRect
    }

    private func geometry() -> Geometry {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        let notch = screen.safeAreaInsets.top   // 有刘海≈32-38，无刘海=0
        let collapsedH = max(notch, 2)
        let x = frame.midX - width / 2
        let topY = frame.maxY
        return Geometry(
            collapsed: NSRect(x: x, y: topY - collapsedH, width: width, height: collapsedH),
            expanded: NSRect(x: x, y: topY - fullHeight, width: width, height: fullHeight)
        )
    }

    // MARK: - 展示

    private func present(_ post: FeedPost) {
        isShowing = true
        let geo = geometry()
        jlog("present 弹窗，collapsed=\(geo.collapsed) expanded=\(geo.expanded)")
        AnalyticsService.notificationShown(postID: post.id)
        let panel = ensurePanel()

        // 关键：先把面板恢复成展开尺寸，让内容视图在正确的容器大小下完成锚定，
        // 否则复用面板时（上一次结束后处于折叠态）顶部锚定会算错，导致内容显示不全。
        panel.setFrame(geo.expanded, display: false)

        // 重建内容视图。
        container?.subviews.forEach { $0.removeFromSuperview() }
        let card = NotchCardView(
            title: post.authorName,
            bodyText: post.content.isEmpty ? "发布了新动态" : post.content,
            avatarURL: post.authorAvatarURL,
            onTap: { [weak self] in self?.handleTap(post) }
        )
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: width, height: fullHeight)
        host.autoresizingMask = [.minYMargin]   // 顶部固定、高度固定；面板变矮时底部被裁
        container?.addSubview(host)

        // 折叠态作为动画起点，从"刘海"展开。
        panel.setFrame(geo.collapsed, display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(geo.expanded, display: true)
        }

        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    private func dismiss() {
        guard let panel else { isShowing = false; return }
        let geo = geometry()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(geo.collapsed, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                panel.orderOut(nil)
                self.isShowing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + self.gapBetween) {
                    self.showNextIfIdle()
                }
            }
        })
    }

    private func handleTap(_ post: FeedPost) {
        AnalyticsService.notificationClicked(postID: post.id)
        if let url = post.webURL {
            NSWorkspace.shared.open(url)
        }
        dismissWork?.cancel()
        dismiss()
    }

    // MARK: - Panel 构造（懒加载，复用）

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let geo = geometry()
        let panel = NSPanel(
            contentRect: geo.expanded,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: geo.expanded.size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        panel.contentView = container

        self.panel = panel
        self.container = container
        return panel
    }
}
