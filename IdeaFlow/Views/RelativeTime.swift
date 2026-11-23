import Foundation

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh-CN")
        f.unitsStyle = .short
        return f
    }()

    /// "2分钟前" / "昨天" / "3天前"
    static func string(from date: Date, to reference: Date = Date()) -> String {
        let interval = reference.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400))天前" }
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
