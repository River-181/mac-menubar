import XCTest
@testable import NotchDock

final class DropRoutingEngineTests: XCTestCase {
    func testTargetedActionWins() {
        let engine = DropRoutingEngine()
        let plan = DropPlan(kind: .images, recommendedAction: .optimizeImages, secondaryActions: [.compressZip])
        let selected = engine.resolveAction(
            plan: plan,
            targeted: .compressZip,
            telemetry: DropTelemetry(point: .zero, velocity: .zero, timestamp: 0)
        )
        XCTAssertEqual(selected, .compressZip)
    }

    func testRecommendedActionFallback() {
        let engine = DropRoutingEngine()
        let plan = DropPlan(kind: .pdfs, recommendedAction: .optimizePDFKeepText, secondaryActions: [.pdfToImages])
        let selected = engine.resolveAction(plan: plan, targeted: nil, telemetry: nil)
        XCTAssertEqual(selected, .optimizePDFKeepText)
    }

    func testSecondaryFallbackIsDeterministic() {
        let engine = DropRoutingEngine()
        let plan = DropPlan(kind: .mixed, recommendedAction: nil, secondaryActions: [.compressZip, .moveToTrash])
        let selected = engine.resolveAction(
            plan: plan,
            targeted: nil,
            telemetry: DropTelemetry(point: .zero, velocity: CGVector(dx: -900, dy: 0), timestamp: 0)
        )
        XCTAssertEqual(selected, .compressZip)
    }
}
