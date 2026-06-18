import Foundation
import FirebaseCore
import FirebaseAnalytics

/// Firebase Analytics 封装：从 .app 包内的 GoogleService-Info.plist 初始化，并提供事件上报。
enum AnalyticsService {

    /// 启动时调用一次。读取 Bundle 内的 GoogleService-Info.plist 配置 Firebase。
    static func configure() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            jlog("未找到 GoogleService-Info.plist，跳过 Firebase 初始化")
            return
        }
        FirebaseApp.configure(options: options)
        // plist 里 IS_ANALYTICS_ENABLED=false，显式打开采集。
        Analytics.setAnalyticsCollectionEnabled(true)
        jlog("Firebase Analytics 已初始化（project=\(options.projectID ?? "?")）")
    }

    static func log(_ name: String, _ params: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: params)
    }

    // MARK: - 语义化事件

    static func loginSuccess() {
        log("jbar_login_success")
    }

    static func feedRefresh(fetched: Int, new: Int) {
        log("jbar_feed_refresh", ["fetched_count": fetched, "new_count": new])
    }

    static func notificationShown(postID: String) {
        log("jbar_notification_shown", ["post_id": postID])
    }

    static func notificationClicked(postID: String) {
        log("jbar_notification_clicked", ["post_id": postID])
    }
}
