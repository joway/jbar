import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let auth = AuthManager()
    private let notifier = NotchNotifier()
    private lazy var poller = FeedPoller(auth: auth, notifier: notifier)
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        jlog("JBar 启动")
        AnalyticsService.configure()
        menuBar = MenuBarController(auth: auth, poller: poller, notifier: notifier)

        auth.onStateChange = { [weak self] state in
            guard let self else { return }
            self.menuBar.update(for: state)
            switch state {
            case .loggedIn:
                self.poller.start()
            case .loggedOut:
                self.poller.stop()
            case .loggingIn:
                break
            }
        }

        // 启动时：有 token 直接进入已登录态，否则弹出扫码登录。
        auth.bootstrap()

        // 调试：设置 JBAR_TEST_NOTIFY 环境变量时，启动后自动弹一条测试通知。
        if ProcessInfo.processInfo.environment["JBAR_TEST_NOTIFY"] != nil {
            jlog("已计划测试通知（+1.5s）")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                jlog("触发测试通知")
                self?.notifier.enqueueTest()
            }
        }
    }
}
