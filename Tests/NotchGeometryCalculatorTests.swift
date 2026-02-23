import XCTest
@testable import NotchDock

final class NotchGeometryCalculatorTests: XCTestCase {
    func testAdaptiveAutoWithNotchUsesCompactSpacingRange() {
        let snapshot = NotchGeometryCalculator.calculateLayout(
            screenWidth: 1512,
            safeLeft: 674,
            safeRight: 674,
            policy: .adaptiveAuto,
            fullscreenLike: false
        )

        XCTAssertTrue(snapshot.hasNotch)
        XCTAssertTrue(snapshot.compactMode)
        XCTAssertGreaterThanOrEqual(snapshot.spacing, 3.5)
        XCTAssertLessThanOrEqual(snapshot.spacing, 9.5)
    }

    func testAlwaysRespectDisablesCompact() {
        let snapshot = NotchGeometryCalculator.calculateLayout(
            screenWidth: 3440,
            safeLeft: 0,
            safeRight: 0,
            policy: .alwaysRespect,
            fullscreenLike: false
        )

        XCTAssertFalse(snapshot.compactMode)
        XCTAssertGreaterThanOrEqual(snapshot.spacing, 6)
    }

    func testFullscreenLikeAppliesAdditionalDamping() {
        let normal = NotchGeometryCalculator.calculateLayout(
            screenWidth: 1800,
            safeLeft: 0,
            safeRight: 0,
            policy: .alwaysCompact,
            fullscreenLike: false
        )
        let fullscreen = NotchGeometryCalculator.calculateLayout(
            screenWidth: 1800,
            safeLeft: 0,
            safeRight: 0,
            policy: .alwaysCompact,
            fullscreenLike: true
        )

        XCTAssertLessThan(fullscreen.spacing, normal.spacing)
    }

    func testHitMaskRectExpandsBeyondVisualCapsuleBounds() {
        let calculator = NotchGeometryCalculator()
        let panelFrame = CGRect(x: 500, y: 900, width: 800, height: 360)
        let mask = calculator.hitMaskRect(for: .peek, panelFrame: panelFrame)

        XCTAssertGreaterThan(mask.width, DockOverlayState.peek.capsuleSize.width)
        XCTAssertGreaterThan(mask.height, DockOverlayState.peek.capsuleSize.height)
        XCTAssertLessThan(mask.minY, panelFrame.maxY)
    }

    func testHitMaskExpansionUsesNotchProfile() {
        let noNotch = NotchLayoutSnapshot(
            screenWidth: 1728,
            safeLeft: 0,
            safeRight: 0,
            hasNotch: false,
            compactMode: false,
            spacing: 8
        )
        let wideNotch = NotchLayoutSnapshot(
            screenWidth: 1512,
            safeLeft: 620,
            safeRight: 620,
            hasNotch: true,
            compactMode: true,
            spacing: 8
        )

        let noNotchInsets = NotchGeometryCalculator.hitMaskExpansion(for: .peek, snapshot: noNotch)
        let wideNotchInsets = NotchGeometryCalculator.hitMaskExpansion(for: .peek, snapshot: wideNotch)

        XCTAssertGreaterThan(wideNotchInsets.horizontal, noNotchInsets.horizontal)
        XCTAssertGreaterThan(wideNotchInsets.vertical, noNotchInsets.vertical)
    }

    func testExpandedStateUsesTighterHitMaskThanPeek() {
        let snapshot = NotchLayoutSnapshot(
            screenWidth: 1512,
            safeLeft: 620,
            safeRight: 620,
            hasNotch: true,
            compactMode: true,
            spacing: 8
        )

        let peekInsets = NotchGeometryCalculator.hitMaskExpansion(for: .peek, snapshot: snapshot)
        let expandInsets = NotchGeometryCalculator.hitMaskExpansion(for: .expand, snapshot: snapshot)

        XCTAssertGreaterThan(peekInsets.horizontal, expandInsets.horizontal)
        XCTAssertGreaterThan(peekInsets.vertical, expandInsets.vertical)
    }
}
