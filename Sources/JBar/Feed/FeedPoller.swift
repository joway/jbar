import AppKit

/// 定时拉取关注流，检测新动态并交给 NotchNotifier 弹通知。
@MainActor
final class FeedPoller {
    var interval: TimeInterval = 60

    private let auth: AuthManager
    private let notifier: NotchNotifier
    private let api = JikeAPIClient.shared
    private let store = SeenStore()

    private var timer: Timer?
    private var isPolling = false

    init(auth: AuthManager, notifier: NotchNotifier) {
        self.auth = auth
        self.notifier = notifier
    }

    func start() {
        stop()
        jlog("开始轮询关注流，间隔 \(Int(interval))s")
        Task { await poll() }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 手动刷新（菜单"立即刷新"）。
    func refreshNow() async {
        await poll()
    }

    /// 调试：拉取关注流最新一条动态并直接弹通知（不影响去重基线）。
    func showLatestAsNotification() async {
        guard let token = await auth.currentAccessToken() else {
            jlog("弹出最新动态：未登录")
            return
        }
        do {
            let result = try await api.followingUpdates(accessToken: token, limit: 1)
            if let post = result.posts.first {
                notifier.enqueue(post)
            } else {
                jlog("弹出最新动态：关注流为空")
            }
        } catch JikeAPIError.notAuthenticated {
            if await auth.refreshIfPossible(), let newToken = await auth.currentAccessToken(),
               let result = try? await api.followingUpdates(accessToken: newToken, limit: 1),
               let post = result.posts.first {
                notifier.enqueue(post)
            }
        } catch {
            jlog("弹出最新动态失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 轮询

    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        guard let token = await auth.currentAccessToken() else {
            jlog("轮询跳过：未登录")
            return
        }
        do {
            let result = try await api.followingUpdates(accessToken: token)
            handle(result.posts)
        } catch JikeAPIError.notAuthenticated {
            jlog("401，尝试刷新 token 后重试一次")
            if await auth.refreshIfPossible(), let newToken = await auth.currentAccessToken() {
                if let result = try? await api.followingUpdates(accessToken: newToken) {
                    handle(result.posts)
                }
            }
        } catch {
            jlog("轮询失败：\(error.localizedDescription)")
        }
    }

    private func handle(_ posts: [FeedPost]) {
        guard !posts.isEmpty else { return }
        let ids = posts.map(\.id)

        if !store.baselineDone {
            store.merge(ids)
            store.baselineDone = true
            jlog("已建立基线（\(ids.count) 条），首次不通知")
            return
        }

        let seen = store.seenIds()
        let newPosts = posts.filter { !seen.contains($0.id) }
        jlog("拉取 \(posts.count) 条，新增 \(newPosts.count) 条")
        AnalyticsService.feedRefresh(fetched: posts.count, new: newPosts.count)

        // 从旧到新依次弹出（关注流通常新→旧，reverse 让最旧的先弹）。
        for post in newPosts.reversed() {
            notifier.enqueue(post)
        }
        store.merge(ids)
    }
}
