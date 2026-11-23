import Foundation
import SwiftUI
import LocalAuthentication
import UserNotifications

/// Face ID 锁(DESIGN §14):可选开启,默认关。
/// 相位策略:退后台上锁、真回前台(前一相位为 background)自动验证;
/// 验证弹窗自身的 scenePhase 抖动靠防重入门闩 + 相位判断拦住——
/// 否则弹窗出现/消失会叠出连环验证直到被系统杀掉(真机实锤 bug)。
@MainActor
final class AppLockService: ObservableObject {
    static let enabledKey = "applock.enabled"

    @Published var isLocked: Bool
    @Published private(set) var isAuthenticating = false

    private var previousPhase: ScenePhase?
    private let defaults: UserDefaults

    /// 验证器注入点(单测替换,不弹系统 UI)
    var canEvaluate: () -> Bool = {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
    var evaluate: (_ reason: String) async throws -> Bool = { reason in
        try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _isLocked = Published(initialValue: defaults.bool(forKey: Self.enabledKey))
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        defer { previousPhase = phase }
        switch phase {
        case .background:
            if isEnabled { isLocked = true }
        case .active:
            // 仅"真回前台"(自 background 或冷启动首激活)自动验证;
            // 弹窗导致的 active→inactive→active 抖动不重弹
            let fromBackground = previousPhase == .background || previousPhase == nil
            if fromBackground, isEnabled, isLocked, !isAuthenticating {
                Task { await self.authenticate() }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func authenticate() async {
        guard !isAuthenticating else { return }   // 防重入:并发只弹一次
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard isEnabled else {
            isLocked = false
            return
        }
        guard canEvaluate() else {
            isLocked = false   // 无 Bio/未设密码环境不拦截
            return
        }
        do {
            let ok = try await evaluate("解锁查看你的灵感")
            isLocked = !ok
        } catch {
            isLocked = true   // 取消/失败保持锁定,用户可手动再试
        }
    }
}

/// 每日回顾提醒(DESIGN §9.5):默认关,开启时每晚固定时间一条。
final class ReminderService {
    static let enabledKey = "reminder.enabled"
    static let hourKey = "reminder.hour"
    static let minuteKey = "reminder.minute"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var time: (hour: Int, minute: Int) {
        get {
            (UserDefaults.standard.integer(forKey: Self.hourKey),
             UserDefaults.standard.integer(forKey: Self.minuteKey))
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: Self.hourKey)
            UserDefaults.standard.set(newValue.minute, forKey: Self.minuteKey)
        }
    }

    func update(enable: Bool, hour: Int = 20, minute: Int = 30) {
        isEnabled = enable
        time = (hour, minute)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-review"])
        guard enable else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "今天的灵感回顾"
            content.body = "花一分钟看看今天记了什么,顺手整理状态吧"
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: "daily-review", content: content, trigger: trigger)
            center.add(request)
        }
    }
}
