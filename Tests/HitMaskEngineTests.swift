import XCTest
@testable import NotchDock

final class HitMaskEngineTests: XCTestCase {
    func testCapsuleMaskContainsCenter() {
        let engine = HitMaskEngine()
        let panelFrame = CGRect(x: 500, y: 800, width: 380, height: 80)
        let center = CGPoint(x: panelFrame.midX, y: panelFrame.midY)
        XCTAssertTrue(
            engine.isInsideCapsule(
                point: center,
                panelFrame: panelFrame,
                state: .peek,
                hasNotch: true,
                notchWidth: 210
            )
        )
    }

    func testCapsuleMaskRejectsFarPoint() {
        let engine = HitMaskEngine()
        let panelFrame = CGRect(x: 500, y: 800, width: 380, height: 80)
        let point = CGPoint(x: panelFrame.minX - 80, y: panelFrame.minY - 80)
        XCTAssertFalse(
            engine.isInsideCapsule(
                point: point,
                panelFrame: panelFrame,
                state: .peek,
                hasNotch: true,
                notchWidth: 210
            )
        )
    }

    func testNotchWiderMaskThanNoNotch() {
        let engine = HitMaskEngine()
        let panelFrame = CGRect(x: 500, y: 800, width: 380, height: 80)
        let noNotch = engine.capsuleMaskFrame(panelFrame: panelFrame, state: .peek, hasNotch: false, notchWidth: 0)
        let notch = engine.capsuleMaskFrame(panelFrame: panelFrame, state: .peek, hasNotch: true, notchWidth: 220)
        XCTAssertGreaterThan(notch.width, noNotch.width)
    }
}
