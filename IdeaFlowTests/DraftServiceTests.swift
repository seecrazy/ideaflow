import XCTest
@testable import IdeaFlow

final class DraftServiceTests: XCTestCase {
    var defaults: UserDefaults!
    var sut: DraftService!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "draft-test-\(UUID().uuidString)")
        sut = DraftService(defaults: defaults)
    }

    override func tearDown() {
        for (k, _) in defaults.dictionaryRepresentation() { defaults.removeObject(forKey: k) }
        super.tearDown()
    }

    func testSaveLoadRoundtrip() {
        sut.save(text: "输入到一半的灵感")
        let draft = sut.load()
        XCTAssertEqual(draft?.text, "输入到一半的灵感")
        XCTAssertNotNil(draft?.savedAt)
    }

    func testClearRemovesDraft() {
        sut.save(text: "x")
        sut.clear()
        XCTAssertNil(sut.load())
    }

    func testOverwriteKeepsLatest() {
        sut.save(text: "第一版")
        sut.save(text: "第二版")
        XCTAssertEqual(sut.load()?.text, "第二版")
    }

    func testBlankTextIsNotStored() {
        sut.save(text: "   ")
        XCTAssertNil(sut.load())
    }

    func testSavedAtAdvances() {
        sut.save(text: "a")
        let t1 = sut.load()?.savedAt
        Thread.sleep(forTimeInterval: 0.02)
        sut.save(text: "b")
        let t2 = sut.load()?.savedAt
        XCTAssertGreaterThan(t2!, t1!)
    }
}
