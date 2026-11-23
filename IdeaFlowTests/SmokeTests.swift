import XCTest
@testable import IdeaFlow

final class SmokeTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertTrue(type(of: RootTabView()) == RootTabView.self)
    }
}
