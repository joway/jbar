import Foundation

/// 封装即刻 (ruguoapp) 的 HTTP 接口。
/// 所有请求统一带 Origin / User-Agent / Content-Type，认证接口带 access-token。
actor JikeAPIClient {
    static let shared = JikeAPIClient()

    private let base = URL(string: "https://api.ruguoapp.com")!
    private let origin = "https://web.okjike.com"
    private let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    // MARK: - 请求构造

    private func makeRequest(
        path: String,
        method: String = "POST",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { req.setValue(accessToken, forHTTPHeaderField: "x-jike-access-token") }
        if let refreshToken { req.setValue(refreshToken, forHTTPHeaderField: "x-jike-refresh-token") }
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else if method == "POST" {
            req.httpBody = "{}".data(using: .utf8)
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw JikeAPIError.unknown("非 HTTP 响应")
        }
        return (data, http)
    }

    /// 从响应（头部优先，其次 body）中提取 token 对。
    private func extractTokens(data: Data, response: HTTPURLResponse) -> JikeTokens? {
        func header(_ name: String) -> String? {
            (response.value(forHTTPHeaderField: name)).flatMap { $0.isEmpty ? nil : $0 }
        }
        var access = header("x-jike-access-token")
        var refresh = header("x-jike-refresh-token")

        if access == nil || refresh == nil,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            access = access ?? (json["x-jike-access-token"] as? String)
            refresh = refresh ?? (json["x-jike-refresh-token"] as? String)
        }
        guard let access, let refresh else { return nil }
        return JikeTokens(accessToken: access, refreshToken: refresh)
    }

    // MARK: - 扫码登录

    /// 创建登录会话，返回 uuid。
    func createSession() async throws -> String {
        let req = makeRequest(path: "sessions.create")
        let (data, http) = try await send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw JikeAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uuid = json["uuid"] as? String else {
            throw JikeAPIError.decoding("缺少 uuid 字段")
        }
        return uuid
    }

    /// 由 uuid 构造扫码用的深链（用于生成二维码）。
    nonisolated func scanDeepLink(uuid: String) -> String {
        let scanURL = "https://www.okjike.com/account/scan?uuid=\(uuid)"
        // 必须严格百分号编码：只放行 RFC3986 unreserved 字符，
        // 否则内层 URL 的 `:/?=` 不会被编码，会破坏外层 deep link 的 query 解析。
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = scanURL.addingPercentEncoding(withAllowedCharacters: allowed) ?? scanURL
        let link = "jike://page.jk/web?url=\(encoded)&displayHeader=false&displayFooter=false"
        jlog("scan deep link: \(link)")
        return link
    }

    /// 轮询扫码确认状态。
    func waitForConfirmation(uuid: String) async throws -> ConfirmationResult {
        let req = makeRequest(
            path: "sessions.wait_for_confirmation",
            method: "GET",
            query: [URLQueryItem(name: "uuid", value: uuid)]
        )
        let (data, http) = try await send(req)
        let reason = http.value(forHTTPHeaderField: "reason") ?? ""
        let hasAccess = (http.value(forHTTPHeaderField: "x-jike-access-token") ?? "").isEmpty == false
        jlog("wait_for_confirmation -> HTTP \(http.statusCode) reason=\"\(reason)\" headerToken=\(hasAccess) bodyLen=\(data.count)")
        switch http.statusCode {
        case 200:
            if let tokens = extractTokens(data: data, response: http) {
                return .confirmed(tokens)
            }
            // 200 但没拿到 token，按未确认处理，继续轮询。
            jlog("200 但未提取到 token，body=\(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
            return .pending
        case 400:
            // 即刻把状态放在响应头 `reason` 里，body 只是网关的 HTML。
            // SESSION_IN_WRONG_STATUS = 尚未扫码/确认，继续轮询。
            if reason == "SESSION_IN_WRONG_STATUS" || reason.isEmpty {
                return .pending
            }
            throw JikeAPIError.http(400, reason)
        default:
            throw JikeAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Token 刷新

    /// 用 refresh token 换新的 token 对。
    func refreshTokens(refreshToken: String) async throws -> JikeTokens {
        let req = makeRequest(path: "app_auth_tokens.refresh", refreshToken: refreshToken)
        let (data, http) = try await send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw JikeAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let tokens = extractTokens(data: data, response: http) else {
            throw JikeAPIError.decoding("刷新响应缺少 token")
        }
        return tokens
    }

    // MARK: - 关注流

    /// 拉取关注流。返回动态列表与下一页的 loadMoreKey。
    func followingUpdates(
        accessToken: String,
        limit: Int = 20,
        loadMoreKey: Any? = nil
    ) async throws -> (posts: [FeedPost], loadMoreKey: Any?) {
        var body: [String: Any] = ["limit": limit]
        if let loadMoreKey { body["loadMoreKey"] = loadMoreKey }
        let req = makeRequest(path: "1.0/personalUpdate/followingUpdates", body: body, accessToken: accessToken)
        let (data, http) = try await send(req)
        guard http.statusCode != 401 else { throw JikeAPIError.notAuthenticated }
        guard (200..<300).contains(http.statusCode) else {
            throw JikeAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JikeAPIError.decoding("关注流响应非 JSON")
        }
        let rawItems = (json["data"] as? [[String: Any]]) ?? []
        let posts = rawItems.compactMap { FeedPost(json: $0) }
        return (posts, json["loadMoreKey"])
    }
}

private extension FeedPost {
    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        let type = (json["type"] as? String) ?? "ORIGINAL_POST"
        let content = (json["content"] as? String) ?? ""
        let user = json["user"] as? [String: Any]
        let authorName = (user?["screenName"] as? String) ?? "即刻用户"
        let avatarString = (user?["avatarImage"] as? [String: Any])?["thumbnailUrl"] as? String
            ?? (user?["avatarImage"] as? [String: Any])?["picUrl"] as? String
        let avatarURL = avatarString.flatMap { URL(string: $0) }

        var created: Date?
        if let createdString = json["createdAt"] as? String {
            created = ISO8601DateFormatter().date(from: createdString)
        }

        self.init(
            id: id,
            type: type,
            content: content,
            authorName: authorName,
            authorAvatarURL: avatarURL,
            createdAt: created
        )
    }
}
