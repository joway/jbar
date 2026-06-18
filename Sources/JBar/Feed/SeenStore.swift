import Foundation

/// 持久化"已见动态 id"，用于检测新动态。首次拉取只建立基线、不通知。
struct SeenStore {
    private let idsKey = "jbar.seenPostIds"
    private let baselineKey = "jbar.baselineDone"
    private let maxIds = 600
    private let defaults = UserDefaults.standard

    var baselineDone: Bool {
        get { defaults.bool(forKey: baselineKey) }
        nonmutating set { defaults.set(newValue, forKey: baselineKey) }
    }

    func seenIds() -> Set<String> {
        Set(defaults.stringArray(forKey: idsKey) ?? [])
    }

    /// 合并新 id 并裁剪到上限（保留较新的）。
    func merge(_ ids: [String]) {
        var ordered = defaults.stringArray(forKey: idsKey) ?? []
        let existing = Set(ordered)
        for id in ids where !existing.contains(id) {
            ordered.append(id)
        }
        if ordered.count > maxIds {
            ordered = Array(ordered.suffix(maxIds))
        }
        defaults.set(ordered, forKey: idsKey)
    }

    func reset() {
        defaults.removeObject(forKey: idsKey)
        defaults.set(false, forKey: baselineKey)
    }
}
