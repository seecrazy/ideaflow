import XCTest
import SwiftUI
@testable import IdeaFlow

@MainActor
final class AppLockServiceTests: XCTestCase {

    private func makeService(enabled: Bool, defaults: UserDefaults) -> AppLockService {
        defaults.set(enabled, forKey: AppLockService.enabledKey)
        return AppLockService(defaults: defaults)
    }

    func testLaunchesLockedWhenEnabled() {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        XCTAssertTrue(sut.isLocked, "开启锁后冷启动应直接呈现锁定")
    }

    func testBackgroundLocksOnlyWhenEnabled() {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        sut.isLocked = false   // 已解锁状态
        sut.handleScenePhase(.inactive)
        XCTAssertFalse(sut.isLocked, "inactive 不应上锁")
        sut.handleScenePhase(.background)
        XCTAssertTrue(sut.isLocked, "退后台应上锁")

        let off = makeService(enabled: false, defaults: UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!)
        off.isLocked = false
        off.handleScenePhase(.background)
        XCTAssertFalse(off.isLocked, "未开启时退后台不上锁")
    }

    func testConcurrentAuthenticateRunsEvaluatorOnce() async {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        let counter = Counter()
        sut.canEvaluate = { true }
        sut.evaluate = { _ in
            await counter.tick(50)   // 模拟系统弹窗期间
            return true
        }
        // 验证弹窗引起的 scenePhase 抖动 → 两次并发 authenticate
        async let a: Void = sut.authenticate()
        async let b: Void = sut.authenticate()
        _ = await (a, b)
        XCTAssertEqual(counter.count, 1, "防重入:并发验证只应弹一次")
        XCTAssertFalse(sut.isLocked)
    }

    func testActiveFromBackgroundAutoPrompts() async {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        let counter = Counter()
        sut.canEvaluate = { true }
        sut.evaluate = { _ in await counter.tick(10) }

        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)   // 真回前台
        await counter.waitForCalls(1, timeout: 2)
        XCTAssertFalse(sut.isLocked, "真回前台应自动验证并解锁")
    }

    func testSceneFlapAfterFailureDoesNotRePrompt() async {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        let counter = Counter()
        sut.canEvaluate = { true }
        sut.evaluate = { _ in
            _ = await counter.tick(10)
            throw NSError(domain: NSOSStatusErrorDomain, code: 0)   // 用户取消等失败
        }

        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)          // 回前台,第一次验证(失败)
        await counter.waitForCalls(1, timeout: 2)
        XCTAssertTrue(sut.isLocked, "取消后保持锁定")

        // 弹窗消失引发的抖动:active → inactive → active 不允许再自动弹
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(counter.count, 1, "抖动重入不应叠加验证弹窗")
        XCTAssertTrue(sut.isLocked)

        // 用户手动点"解锁"仍可验证
        _ = try? await sut.authenticate()
        XCTAssertEqual(counter.count, 2)
    }

    func testNoPasscodeEnvironmentUnlocksInsteadOfLockingForever() async {
        let defaults = UserDefaults(suiteName: "lock-test-\(UUID().uuidString)")!
        let sut = makeService(enabled: true, defaults: defaults)
        sut.canEvaluate = { false }   // 设备未设密码
        await sut.authenticate()
        XCTAssertFalse(sut.isLocked, "无密码环境不应永久锁死")
    }
}

/// 并发计数器(测试辅助):NSLock 版,任意执行器可同步读写
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    func tick(_ ms: UInt64) async -> Bool {
        lock.lock(); _count += 1; lock.unlock()
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
        return true
    }

    func waitForCalls(_ n: Int, timeout: TimeInterval) async {
        let start = Date()
        while count < n, Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
