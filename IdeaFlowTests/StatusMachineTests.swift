import XCTest
import SwiftUI
@testable import IdeaFlow

final class StatusMachineTests: XCTestCase {

    // DESIGN 5.4 流转规则表逐格断言
    func testTransitionMatrixMatchesSpec() {
        let allowed: [IdeaStatus: Set<IdeaStatus>] = [
            .draft:     [.pending, .rejected, .abandoned],
            .pending:   [.adopted, .rejected, .abandoned, .draft],
            .adopted:   [.archived, .abandoned],
            .rejected:  [.draft, .abandoned],
            .abandoned: [.draft, .pending],
            .archived:  [.adopted, .draft],
        ]
        for from in IdeaStatus.allCases {
            for to in IdeaStatus.allCases {
                let expected = allowed[from]!.contains(to)
                XCTAssertEqual(
                    from.canTransition(to: to), expected,
                    "\(from.displayName) → \(to.displayName) 应为 \(expected)"
                )
            }
        }
    }

    func testSelfTransitionAlwaysRejected() {
        for s in IdeaStatus.allCases {
            XCTAssertFalse(s.canTransition(to: s), "\(s.displayName) → 自身不允许")
        }
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(IdeaStatus.draft.rawValue, 0)
        XCTAssertEqual(IdeaStatus.pending.rawValue, 1)
        XCTAssertEqual(IdeaStatus.adopted.rawValue, 2)
        XCTAssertEqual(IdeaStatus.rejected.rawValue, 3)
        XCTAssertEqual(IdeaStatus.abandoned.rawValue, 4)
        XCTAssertEqual(IdeaStatus.archived.rawValue, 5)
        XCTAssertEqual(IdeaStatus(rawValue: 3), .rejected)
        XCTAssertNil(IdeaStatus(rawValue: 99))
    }

    func testDisplayMetadata() {
        XCTAssertEqual(IdeaStatus.draft.displayName, "草稿")
        XCTAssertEqual(IdeaStatus.pending.displayName, "待处理")
        XCTAssertEqual(IdeaStatus.adopted.displayName, "已采纳")
        XCTAssertEqual(IdeaStatus.rejected.displayName, "已拒绝")
        XCTAssertEqual(IdeaStatus.abandoned.displayName, "已废弃")
        XCTAssertEqual(IdeaStatus.archived.displayName, "已归档")
        for s in IdeaStatus.allCases {
            XCTAssertFalse(s.iconName.isEmpty)
        }
    }

    func testArchivedHiddenFromHomeOthersVisible() {
        for s in IdeaStatus.allCases where s != .archived {
            XCTAssertTrue(s.isVisibleOnHome, "\(s.displayName) 应在首页可见")
        }
        XCTAssertFalse(IdeaStatus.archived.isVisibleOnHome)
    }

    // DESIGN 5.3 状态色板(浅/深)
    func testPaletteLightAndDarkHex() {
        let expectations: [(IdeaStatus, UInt32, UInt32)] = [
            (.draft,     0x8E8E93, 0x98989D),
            (.pending,   0x007AFF, 0x0A84FF),
            (.adopted,   0x34C759, 0x30D158),
            (.rejected,  0xFF3B30, 0xFF453A),
            (.abandoned, 0x636366, 0x48484A),
            (.archived,  0xC7C7CC, 0x3A3A3C),
        ]
        for (status, light, dark) in expectations {
            XCTAssertEqual(hex(of: status.color, style: .light), light, "\(status.displayName) 浅色")
            XCTAssertEqual(hex(of: status.color, style: .dark), dark, "\(status.displayName) 深色")
        }
    }

    func testStatusChangeSourceRawValues() {
        XCTAssertEqual(StatusChangeSource.manual.rawValue, 0)
        XCTAssertEqual(StatusChangeSource.batch.rawValue, 1)
        XCTAssertEqual(StatusChangeSource.quickAction.rawValue, 2)
    }

    private func hex(of color: UIColor, style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
    }
}
