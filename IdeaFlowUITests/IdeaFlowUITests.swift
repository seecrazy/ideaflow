import XCTest

/// 端到端用例(DESIGN §16 验收 2/4/5/8 的本地子集)
final class IdeaFlowUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if reset {
            app.launchArguments = ["-uiTestReset"]
        }
        app.launch()
        return app
    }

    /// 确定性输入:入口条 → 速记面板 → 输入 → 校验绑定生效
    private func typeIdea(_ app: XCUIApplication, _ text: String) {
        let entry = app.descendants(matching: .any)["quick_entry_bar"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "入口条应常驻首页")
        entry.tap()
        let field = app.descendants(matching: .any)["capture_content"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "速记面板应弹出")
        usleep(600_000)
        field.tap()
        field.typeText(text)
        usleep(400_000)
        if !(field.value as? String ?? "").contains(text) {
            field.tap()
            usleep(200_000)
            field.typeText(text)
            usleep(600_000)
        }
    }

    private func saveCurrent(_ app: XCUIApplication) {
        let save = app.buttons["capture_save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.keyboards.buttons["return"].tap()
            usleep(400_000)
        }
    }

    private func cardTitled(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    // 用例 1:记录 → 改状态 → 搜索命中(DESIGN 验收 4/5)
    func testRecordStatusSearchFlow() {
        let app = launch(reset: true)

        typeIdea(app, "端到端测试灵感")
        dismissKeyboard(app)
        saveCurrent(app)
        let card = cardTitled(app, "端到端测试灵感")
        XCTAssertTrue(card.waitForExistence(timeout: 8), "保存后卡片应出现在首页")

        card.tap()
        let capsule = app.descendants(matching: .any)["status_capsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 10), "详情应有状态胶囊")
        capsule.tap()
        let pending = app.buttons["转待处理"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.tap()
        let confirm = app.buttons["确认流转"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 搜索命中
        app.tabBars.buttons.element(boundBy: 1).tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("端到端")
        XCTAssertTrue(cardTitled(app, "端到端测试灵感").waitForExistence(timeout: 8), "搜索应命中刚记录的灵感")
    }

    // 用例 2:草稿恢复(DESIGN 验收 2:强杀不丢)
    func testDraftRecoveryAfterRelaunch() {
        let app = launch(reset: true)

        typeIdea(app, "没写完的想法")
        sleep(2)   // 等 500ms 节流落草稿(面板保持打开,模拟被打断)

        app.terminate()
        let relaunched = launch(reset: false)

        let banner = relaunched.otherElements["draft_banner"].firstMatch
        let recovered = relaunched.buttons["继续"].firstMatch
        XCTAssertTrue(recovered.waitForExistence(timeout: 8) || banner.exists, "重启后应出现草稿恢复提示条")
        recovered.tap()
        usleep(800_000)   // 等状态提交渲染

        saveCurrent(relaunched)
        XCTAssertTrue(cardTitled(relaunched, "没写完的想法").waitForExistence(timeout: 8), "草稿应可一键转正式")
    }

    // 用例 3:回收站删除与恢复(DESIGN 验收 8)
    func testRecycleBinRestore() {
        let app = launch(reset: true)

        typeIdea(app, "要删除的灵感")
        dismissKeyboard(app)
        saveCurrent(app)
        let card = cardTitled(app, "要删除的灵感")
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        // 左滑删除(失败则快速再滑一次)
        card.swipeLeft()
        var deleteButton = app.buttons.matching(NSPredicate(format: "label == '删除'")).firstMatch
        if !deleteButton.waitForExistence(timeout: 2) {
            card.swipeLeft(velocity: .fast)
            deleteButton = app.buttons.matching(NSPredicate(format: "label == '删除'")).firstMatch
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "左滑应出现删除")
        }
        deleteButton.tap()
        usleep(800_000)
        XCTAssertFalse(cardTitled(app, "要删除的灵感").exists, "删除后卡片应消失")

        // 回收站 → 恢复 → 返回首页
        app.buttons["回收站"].firstMatch.tap()
        let restore = app.buttons["恢复"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8), "回收站应有已删条目")
        restore.tap()
        usleep(600_000)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(cardTitled(app, "要删除的灵感").waitForExistence(timeout: 8), "恢复后卡片应回到首页")
    }
    // 用例 4:详情页删除 → 返回列表 + 撤销提示 + 一键恢复(删除反馈优化)
    func testDeleteFromDetailShowsToastAndUndo() {
        let app = launch(reset: true)

        typeIdea(app, "详情删除目标")
        saveCurrent(app)
        let card = cardTitled(app, "详情删除目标")
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        card.tap()
        let more = app.buttons["更多操作"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "详情应有更多菜单")
        more.tap()
        let del = app.buttons["移到回收站"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 3))
        del.tap()

        // 反馈一:提示条出现;反馈二:自动回到列表且卡片消失
        XCTAssertTrue(app.descendants(matching: .any)["undo_toast"].firstMatch.waitForExistence(timeout: 4),
                      "删除后应有撤销提示条")
        // 提示条 4 秒自动消失:立即锁定撤销按钮,其余断言后置
        let undo = app.descendants(matching: .any)["undo_button"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "提示条应有撤销按钮")
        XCTAssertTrue(app.descendants(matching: .any)["home_idea_list"].firstMatch.waitForExistence(timeout: 5),
                      "删除后应自动返回列表")
        XCTAssertFalse(cardTitled(app, "详情删除目标").exists, "列表中卡片应已消失")
        undo.tap()
        XCTAssertTrue(cardTitled(app, "详情删除目标").waitForExistence(timeout: 5), "撤销后卡片应恢复")
    }
}
