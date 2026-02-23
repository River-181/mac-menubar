import XCTest
@testable import MacMenubar

final class NotchLayoutCalculatorTests: XCTestCase {
    func testNotchAwareSnapshotCalculation() {
        let snapshot = NotchLayoutCalculator.calculate(
            screenWidth: 1512,
            safeLeft: 674,
            safeRight: 674,
            fullscreenLike: false
        )

        XCTAssertEqual(snapshot.notchWidth, 164, accuracy: 0.001)
        XCTAssertEqual(snapshot.reservedCenterWidth, 212, accuracy: 0.001)
        XCTAssertEqual(snapshot.sideBudget, 650, accuracy: 0.001)
        XCTAssertEqual(snapshot.spacing, 6, accuracy: 0.001)
    }

    func testFullscreenLikeCompactsSpacing() {
        let snapshot = NotchLayoutCalculator.calculate(
            screenWidth: 1280,
            safeLeft: 560,
            safeRight: 560,
            fullscreenLike: true
        )

        XCTAssertLessThan(snapshot.spacing, 14)
        XCTAssertGreaterThanOrEqual(snapshot.spacing, 4)
        XCTAssertTrue(snapshot.fullscreenLike)
    }
}
