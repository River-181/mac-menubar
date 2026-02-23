import XCTest
@testable import NotchDock

final class IconDockServiceTests: XCTestCase {
    func testPinnedItemsRankAboveShelf() {
        let service = IconDockService()
        let now = Date()
        let pinned = DockIcon(
            id: "p",
            source: .manual,
            symbolOrImage: "wifi",
            title: "Pinned",
            bucket: .pinned,
            groupID: "System",
            lastUsedAt: now.addingTimeInterval(-500),
            rank: 0.1
        )
        let shelf = DockIcon(
            id: "s",
            source: .manual,
            symbolOrImage: "terminal",
            title: "Shelf",
            bucket: .shelf,
            groupID: "Dev",
            lastUsedAt: now,
            rank: 1.0
        )

        let sorted = service.sort([shelf, pinned], now: now)
        XCTAssertEqual(sorted.first?.id, "p")
    }

    func testOverflowAppearsWhenCapacityIsExceeded() {
        let service = IconDockService()
        let now = Date()
        let pinned = (0..<3).map { index in
            DockIcon(
                id: "p\(index)",
                source: .manual,
                symbolOrImage: "wifi",
                title: "Pinned \(index)",
                bucket: .pinned,
                groupID: "System",
                lastUsedAt: now,
                rank: 1.0
            )
        }
        let shelf = (0..<8).map { index in
            DockIcon(
                id: "s\(index)",
                source: .manual,
                symbolOrImage: "terminal",
                title: "Shelf \(index)",
                bucket: .shelf,
                groupID: "Dev",
                lastUsedAt: now,
                rank: Double(index)
            )
        }

        let arranged = service.arrange(pinned: pinned, shelf: shelf, state: .peek)
        XCTAssertEqual(arranged.visible.count, 7)
        XCTAssertEqual(arranged.overflow.count, 4)
        XCTAssertTrue(arranged.overflow.allSatisfy { $0.bucket == .overflow })
    }
}
