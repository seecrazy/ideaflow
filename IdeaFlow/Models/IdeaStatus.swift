import SwiftUI

/// 点子状态机(DESIGN §5):枚举化避免硬编码,流转表显式定义便于测试。
enum IdeaStatus: Int16, CaseIterable, Codable {
    case draft      = 0   // 草稿:快速记录的原始素材,未整理
    case pending    = 1   // 待处理:已整理,等待评估
    case adopted    = 2   // 已采纳:决定执行/采用
    case rejected   = 3   // 已拒绝:评估后不采用
    case abandoned  = 4   // 已废弃:执行中放弃 / 失效
    case archived   = 5   // 已归档:完成或长期存放

    var displayName: String {
        switch self {
        case .draft:     return "草稿"
        case .pending:   return "待处理"
        case .adopted:   return "已采纳"
        case .rejected:  return "已拒绝"
        case .abandoned: return "已废弃"
        case .archived:  return "已归档"
        }
    }

    var iconName: String {
        switch self {
        case .draft:     return "square.and.pencil"
        case .pending:   return "hourglass"
        case .adopted:   return "checkmark.circle.fill"
        case .rejected:  return "xmark.circle"
        case .abandoned: return "minus.circle"
        case .archived:  return "archivebox"
        }
    }

    /// 浅色/深色双值动态色(DESIGN 5.3 色板)
    var color: UIColor {
        switch self {
        case .draft:
            return UIColor(light: 0x8E8E93, dark: 0x98989D)
        case .pending:
            return UIColor(light: 0x007AFF, dark: 0x0A84FF)
        case .adopted:
            return UIColor(light: 0x34C759, dark: 0x30D158)
        case .rejected:
            return UIColor(light: 0xFF3B30, dark: 0xFF453A)
        case .abandoned:
            return UIColor(light: 0x636366, dark: 0x48484A)
        case .archived:
            return UIColor(light: 0xC7C7CC, dark: 0x3A3A3C)
        }
    }

    var swiftUIColor: Color { Color(color) }

    /// 归档状态不占首页(DESIGN 5.1)
    var isVisibleOnHome: Bool { self != .archived }

    /// DESIGN 5.4 流转规则表。原则:不设死锁,任意状态都能回到草稿重新开始。
    var allowedTransitions: [IdeaStatus] {
        switch self {
        case .draft:     return [.pending, .rejected, .abandoned]
        case .pending:   return [.adopted, .rejected, .abandoned, .draft]
        case .adopted:   return [.archived, .abandoned]
        case .rejected:  return [.draft, .abandoned]
        case .abandoned: return [.draft, .pending]
        case .archived:  return [.adopted, .draft]
        }
    }

    func canTransition(to target: IdeaStatus) -> Bool {
        target != self && allowedTransitions.contains(target)
    }
}

/// 状态变更来源(DESIGN 5.6):手动 / 批量 / 快捷操作
enum StatusChangeSource: Int16, CaseIterable, Codable {
    case manual     = 0
    case batch      = 1
    case quickAction = 2

    var displayName: String {
        switch self {
        case .manual:      return "手动"
        case .batch:       return "批量"
        case .quickAction: return "快捷操作"
        }
    }
}

extension UIColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1
            )
        }
    }
}
