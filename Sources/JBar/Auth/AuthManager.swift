import AppKit

/// 登录状态。
enum AuthState: Equatable {
    case loggedOut
    case loggingIn(status: String)
    case loggedIn
}

/// 负责 token 生命周期：启动引导、扫码登录、刷新、登出。
@MainActor
final class AuthManager {
    private(set) var state: AuthState = .loggedOut {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((AuthState) -> Void)?

    private let api = JikeAPIClient.shared
    private var loginWindow: QRLoginWindowController?
    private var loginTask: Task<Void, Never>?

    // token 改存文件（TokenStore）。文件 I/O 也放后台线程，避免阻塞主线程上的 UI。
    private func read(_ key: TokenStore.Key) async -> String? {
        await Task.detached(priority: .userInitiated) { TokenStore.get(key) }.value
    }

    private func write(_ value: String?, _ key: TokenStore.Key) async {
        await Task.detached(priority: .userInitiated) { TokenStore.set(value, for: key) }.value
    }

    /// 供轮询使用的 access token（后台读取）。
    func currentAccessToken() async -> String? { await read(.accessToken) }

    // MARK: - 启动引导

    func bootstrap() {
        // 一次性清理旧的 Keychain token（SecItemDelete 不弹授权框）；已迁移到文件存储。
        Task.detached { KeychainStore.clear() }
        Task { [weak self] in
            guard let self else { return }
            let access = await self.read(.accessToken)
            let refresh = await self.read(.refreshToken)
            if access != nil, refresh != nil {
                self.state = .loggedIn
            } else {
                self.startQRLogin()
            }
        }
    }

    // MARK: - 扫码登录

    func startQRLogin() {
        loginTask?.cancel()
        state = .loggingIn(status: "正在创建登录会话…")

        let window = loginWindow ?? QRLoginWindowController()
        loginWindow = window
        window.onCancel = { [weak self] in self?.cancelLogin() }
        window.show()
        window.update(status: "正在创建登录会话…", qr: nil)

        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let uuid = try await self.api.createSession()
                jlog("创建会话成功 uuid=\(uuid)")
                let deepLink = self.api.scanDeepLink(uuid: uuid)
                let qr = QRCodeGenerator.image(from: deepLink)
                window.update(status: "请用即刻 App 扫码登录", qr: qr)
                self.state = .loggingIn(status: "等待扫码…")

                let tokens = try await self.pollConfirmation(uuid: uuid)
                await self.completeLogin(with: tokens)
            } catch is CancellationError {
                // 用户取消，忽略。
            } catch {
                window.update(status: "登录失败：\(error.localizedDescription)\n点击重试", qr: nil)
                self.state = .loggedOut
            }
        }
    }

    /// 每秒轮询一次，最多约 3 分钟。
    private func pollConfirmation(uuid: String) async throws -> JikeTokens {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let result = try await api.waitForConfirmation(uuid: uuid)
            switch result {
            case .confirmed(let tokens):
                return tokens
            case .pending:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw JikeAPIError.sessionTimeout
    }

    private func completeLogin(with tokens: JikeTokens) async {
        jlog("登录成功，access token 前缀=\(tokens.accessToken.prefix(8))… 已写入 Keychain")
        await write(tokens.accessToken, .accessToken)
        await write(tokens.refreshToken, .refreshToken)
        loginWindow?.close()
        loginWindow = nil
        state = .loggedIn
        AnalyticsService.loginSuccess()
    }

    private func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginWindow?.close()
        loginWindow = nil
        Task { [weak self] in
            guard let self else { return }
            if await self.read(.accessToken) == nil { self.state = .loggedOut }
        }
    }

    // MARK: - Token 刷新

    /// 用 refresh token 换新 token；失败则视为登出。
    @discardableResult
    func refreshIfPossible() async -> Bool {
        guard let refresh = await read(.refreshToken) else {
            state = .loggedOut
            return false
        }
        do {
            let tokens = try await api.refreshTokens(refreshToken: refresh)
            await write(tokens.accessToken, .accessToken)
            await write(tokens.refreshToken, .refreshToken)
            return true
        } catch {
            logout()
            return false
        }
    }

    // MARK: - 登出

    func logout() {
        Task.detached {
            TokenStore.clear()
            KeychainStore.clear()   // 顺手清理旧的 Keychain 项
        }
        state = .loggedOut
    }
}
