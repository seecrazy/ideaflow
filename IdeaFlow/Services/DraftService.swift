import Foundation

/// 草稿保护(DESIGN §4.3):轻量文本走 UserDefaults,输入即存,App 被杀不丢。
/// 节流由调用方(QuickInputBar 500ms)控制,本服务同步幂等。
final class DraftService {
    struct Draft: Equatable {
        let text: String
        let savedAt: Date
    }

    private static let textKey = "ideaflow.draft.text"
    private static let dateKey = "ideaflow.draft.savedAt"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var draft: Draft? { load() }

    func load() -> Draft? {
        guard let text = defaults.string(forKey: Self.textKey),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let date = defaults.object(forKey: Self.dateKey) as? Date else { return nil }
        return Draft(text: text, savedAt: date)
    }

    func save(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            return
        }
        defaults.set(text, forKey: Self.textKey)
        defaults.set(Date(), forKey: Self.dateKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.textKey)
        defaults.removeObject(forKey: Self.dateKey)
    }
}
