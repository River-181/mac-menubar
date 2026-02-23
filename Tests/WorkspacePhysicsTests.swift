import XCTest
@testable import NotchDock

final class WorkspacePhysicsTests: XCTestCase {
    func testAttractionStrengthCurve() {
        let physics = WorkspacePhysics(config: MagnetConfig(radius: 110, snapThreshold: 60))

        XCTAssertEqual(physics.attractionStrength(distance: 150), 0, accuracy: 0.0001)
        XCTAssertEqual(physics.attractionStrength(distance: 60), 1, accuracy: 0.0001)

        let mid = physics.attractionStrength(distance: 85)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testSnapThreshold() {
        let physics = WorkspacePhysics(config: MagnetConfig(radius: 110, snapThreshold: 60))
        XCTAssertTrue(physics.shouldSnap(distance: 59.9))
        XCTAssertFalse(physics.shouldSnap(distance: 60.1))
    }

    func testOrbitRadiusPerRing() {
        let physics = WorkspacePhysics()
        XCTAssertEqual(physics.orbitRadius(for: 0), 72)
        XCTAssertEqual(physics.orbitRadius(for: 8), 112)
        XCTAssertEqual(physics.orbitRadius(for: 16), 152)
    }
}
