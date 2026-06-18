import Foundation

/// 基于文件的 token 存储：~/Library/Application Support/JBar/tokens.json（权限 0600）。
/// 取代 Keychain，避免 ad-hoc 签名变化导致每次启动都弹授权框。
enum TokenStore {
    enum Key: String {
        case accessToken = "x-jike-access-token"
        case refreshToken = "x-jike-refresh-token"
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("JBar", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        return dir.appendingPathComponent("tokens.json")
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func get(_ key: Key) -> String? {
        let value = load()[key.rawValue]
        return (value?.isEmpty == false) ? value : nil
    }

    static func set(_ value: String?, for key: Key) {
        var dict = load()
        if let value, !value.isEmpty {
            dict[key.rawValue] = value
        } else {
            dict.removeValue(forKey: key.rawValue)
        }
        save(dict)
    }

    static func remove(_ key: Key) { set(nil, for: key) }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
