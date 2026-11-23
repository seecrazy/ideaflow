import Foundation
import LocalAuthentication
import UserNotifications

/// Face ID 锁(DESIGN §14):可选开启,默认关。
@MainActor
final class AppLockService: ObservableObject {
    static let enabledKey = "applock.enabled"

    @Published var isLocked = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    /// 进入前台时调用;开启则先锁再验证
    func handleBecomeActive() {
        guard isEnabled else { return }
        isLocked = true
        Task { await authenticate() }
    }

    func authenticate() async {
        let ctx = LAContext()
        var error: NSError?
        let can = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        guard can else {
            // 无 Bio/无密码环境:不拦截
            isLocked = false
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "解锁查看你的灵感")
            isLocked = !ok
        } catch {
            isLocked = true   // 验证失败保持锁定,用户可再试
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
