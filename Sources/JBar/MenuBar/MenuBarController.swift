import AppKit

/// 菜单栏图标与下拉菜单。
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let auth: AuthManager
    private let poller: FeedPoller
    private let notifier: NotchNotifier
    private let statusMenuItem = NSMenuItem(title: "未登录", action: nil, keyEquivalent: "")

    init(auth: AuthManager, poller: FeedPoller, notifier: NotchNotifier) {
        self.auth = auth
        self.poller = poller
        self.notifier = notifier
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = JBarIcon.statusBarImage()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        // 「测试通知」仅在启动时设置了 JBAR_DEBUG 环境变量才显示，避免打扰普通用户。
        if ProcessInfo.processInfo.environment["JBAR_DEBUG"] != nil {
            let test = NSMenuItem(title: "测试通知", action: #selector(testNotification), keyEquivalent: "t")
            test.target = self
            menu.addItem(test)
        }

        let relogin = NSMenuItem(title: "重新登录", action: #selector(reLogin), keyEquivalent: "")
        relogin.target = self
        menu.addItem(relogin)

        let logout = NSMenuItem(title: "登出", action: #selector(logout), keyEquivalent: "")
        logout.target = self
        menu.addItem(logout)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 JBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - 状态更新

    func update(for state: AuthState) {
        switch state {
        case .loggedOut:
            statusMenuItem.title = "未登录"
        case .loggingIn(let status):
            statusMenuItem.title = status
        case .loggedIn:
            statusMenuItem.title = "已登录"
        }
    }

    // MARK: - 菜单动作

    @objc private func refreshNow() {
        Task { await poller.refreshNow() }
    }

    @objc private func testNotification() {
        Task { await poller.showLatestAsNotification() }
    }

    @objc private func reLogin() {
        auth.startQRLogin()
    }

    @objc private func logout() {
        auth.logout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
