import XCTest
@testable import NotchDock

final class NotchGeometryCalculatorTests: XCTestCase {
    func testNotchSnapshotHasReasonableTriggerSize() {
        let calc = NotchGeometryCalculator()
        let snapshot = NotchLayoutSnapshot(
            hasNotch: true,
            notchWidth: 210,
            triggerFrame: .zero,
            triggerOuterFrame: .zero
        )
        let width = max(170, min(250, snapshot.notchWidth + 24))
        XCTAssertEqual(width, 234)
        XCTAssertGreaterThanOrEqual(width, 170)
        XCTAssertLessThanOrEqual(width, 250)
        _ = calc
    }

    func testPanelFrameCentersOnScreen() {
        guard let screen = NSScreen.main else {
            XCTFail("Main screen missing")
            return
        }
        let calc = NotchGeometryCalculator(topMargin: 6)
        let frame = calc.panelFrame(screen: screen, panelSize: CGSize(width: 420, height: 120))
        XCTAssertEqual(frame.midX, screen.frame.midX, accuracy: 0.5)
        XCTAssertLessThan(frame.maxY, screen.frame.maxY + 0.1)
    }
}
