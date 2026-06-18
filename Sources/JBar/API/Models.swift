import Foundation

/// 一对即刻 token。
struct JikeTokens {
    var accessToken: String
    var refreshToken: String
}

/// 扫码确认轮询的结果。
enum ConfirmationResult {
    case pending                 // 尚未扫码 / 尚未确认，继续轮询
    case confirmed(JikeTokens)   // 已确认，拿到 token
}

/// 关注流里的一条动态（仅保留通知所需字段）。
struct FeedPost: Identifiable {
    let id: String          // originalPosts 的 id，用于拼接网页链接
    let type: String        // ORIGINAL_POST / REPOST 等
    let content: String
    let authorName: String
    let authorAvatarURL: URL?
    let createdAt: Date?

    var webURL: URL? {
        URL(string: "https://m.okjike.com/originalPosts/\(id)")
    }
}

/// 即刻接口错误。
enum JikeAPIError: LocalizedError {
    case notAuthenticated
    case http(Int, String)
    case decoding(String)
    case sessionTimeout
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "未登录或登录已失效"
        case .http(let code, let msg): return "请求失败 (HTTP \(code)) \(msg)"
        case .decoding(let msg): return "响应解析失败：\(msg)"
        case .sessionTimeout: return "扫码超时，请重试"
        case .unknown(let msg): return msg
        }
    }
}
