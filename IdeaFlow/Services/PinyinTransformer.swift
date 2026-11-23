import Foundation

/// 汉字 → 拼音(DESIGN §6 优化决策):CFStringTransform 零第三方依赖。
/// 单字转换结果按字缓存(串行使用场景下仍加锁保护)。
enum PinyinTransformer {

    static func full(_ text: String) -> String { analyze(text).full }
    static func initials(_ text: String) -> String { analyze(text).initials }

    /// full:汉字全拼连写(weixindushu);initials:汉字取声母首字母、英文单词/数字原样保留(wxreadbj)
    static func analyze(_ text: String) -> (full: String, initials: String) {
        var fullParts: [String] = []
        var initialParts: [String] = []
        var latinRun = ""

        func flushLatin() {
            guard !latinRun.isEmpty else { return }
            fullParts.append(latinRun)
            initialParts.append(latinRun)
            latinRun = ""
        }

        for ch in text {
            if isHan(ch) {
                flushLatin()
                if let syllable = syllable(for: ch), !syllable.isEmpty {
                    fullParts.append(syllable)
                    initialParts.append(String(syllable.prefix(1)))
                }
            } else if ch.isLetter || ch.isNumber {
                latinRun.append(ch.lowercased())
            } else {
                flushLatin()
            }
        }
        flushLatin()
        return (fullParts.joined(), initialParts.joined())
    }

    static func isHan(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK 统一表意
             0x3400...0x4DBF,   // 扩展 A
             0xF900...0xFAFF:   // 兼容表意
            return true
        default:
            return false
        }
    }

    private static let cacheLock = NSLock()
    private static nonisolated(unsafe) var cache: [Character: String] = [:]

    private static func syllable(for ch: Character) -> String? {
        cacheLock.lock()
        if let hit = cache[ch] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let mutable = NSMutableString(string: String(ch))
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let result = (mutable as String).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        cacheLock.lock()
        cache[ch] = result
        cacheLock.unlock()
        return result
    }
}
