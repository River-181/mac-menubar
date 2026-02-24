import XCTest
@testable import NotchDock

final class IconPolicyEngineTests: XCTestCase {
    func testPinnedIsPrioritized() {
        let engine = IconPolicyEngine()
        let icons = [
            DockIcon(id: "shelf", title: "Shelf", symbolName: "terminal", bucket: .shelf, rank: 1, isEnabled: true),
            DockIcon(id: "pinned", title: "Pinned", symbolName: "wifi", bucket: .pinned, rank: 5, isEnabled: true)
        ]
        let result = engine.arrange(icons: icons, state: .peek)
        XCTAssertEqual(result.visible.first?.id, "pinned")
    }

    func testOverflowWhenExpandedLimitExceeded() {
        let engine = IconPolicyEngine()
        let icons = (0..<20).map {
            DockIcon(
                id: "icon-\($0)",
                title: "Icon \($0)",
                symbolName: "circle",
                bucket: $0 < 4 ? .pinned : .shelf,
                rank: $0,
                isEnabled: true
            )
        }
        let result = engine.arrange(icons: icons, state: .expand)
        XCTAssertEqual(result.visible.count, 14)
        XCTAssertEqual(result.overflow.count, 6)
        XCTAssertTrue(result.overflow.allSatisfy { $0.bucket == .overflow })
    }
}
