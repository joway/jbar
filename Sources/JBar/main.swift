import AppKit

// 让日志即时落盘，便于从终端调试（否则后台运行被 kill 时缓冲区丢失）。
setvbuf(stdout, nil, _IONBF, 0)
setvbuf(stderr, nil, _IONBF, 0)

// JBar — 即刻关注流的 macOS 菜单栏通知应用
// 入口：以 .accessory 模式运行（无 Dock 图标，仅菜单栏）。

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
