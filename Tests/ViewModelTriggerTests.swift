import XCTest
@testable import NotchDock

@MainActor
final class ViewModelTriggerTests: XCTestCase {
    func testDragInsideTriggerImmediatelyExpands() async {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.overlayState, .hidden)

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: true
        )

        XCTAssertEqual(viewModel.overlayState, .expand)
        XCTAssertTrue(viewModel.isDragSessionActive)
    }

    func testDragOutsideTriggerDoesNotExpand() async {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.overlayState, .hidden)

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: false,
            isTriggerOuterInside: false,
            isCapsuleInside: false,
            isDragging: true
        )

        XCTAssertEqual(viewModel.overlayState, .hidden)
        XCTAssertFalse(viewModel.isDragSessionActive)
    }

    func testHoveredActionClearsWhenDragLeavesTrigger() async {
        let viewModel = makeViewModel()

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: true
        )
        viewModel.setHoveredAction(.compressZip)

        viewModel.ingestPointerSample(
            DropTelemetry(point: CGPoint(x: 80, y: 20), velocity: .zero, timestamp: 0.1),
            isTriggerRawInside: false,
            isTriggerOuterInside: false,
            isCapsuleInside: false,
            isDragging: true
        )

        // Target action is cleared immediately even while the drag continues
        XCTAssertNil(viewModel.targetedAction)
        // Session stays active while isDragging is true (fix A — session only ends when !isDragging)
        XCTAssertTrue(viewModel.isDragSessionActive)
    }

    func testQuickTriggerFlapDoesNotEnterPeek() async {
        let viewModel = makeViewModel()

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: false
        )
        XCTAssertEqual(viewModel.overlayState, .armed)

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0.01),
            isTriggerRawInside: false,
            isTriggerOuterInside: false,
            isCapsuleInside: false,
            isDragging: false
        )

        XCTAssertEqual(viewModel.overlayState, .hidden)
    }

    func testLeaveGraceCollapsesPeekToHidden() async {
        let viewModel = makeViewModel()
        viewModel.transition(.pointerEnterTrigger)
        XCTAssertEqual(viewModel.overlayState, .peek)

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 1),
            isTriggerRawInside: false,
            isTriggerOuterInside: false,
            isCapsuleInside: false,
            isDragging: false
        )

        let expectation = expectation(description: "leave grace collapse")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            XCTAssertEqual(viewModel.overlayState, .hidden)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testClickTransitionsFromHiddenArmedAndPeekIntoExpand() async {
        let viewModel = makeViewModel()

        viewModel.toggleExpand()
        XCTAssertEqual(viewModel.overlayState, .expand)

        viewModel.closeOneLevel()
        XCTAssertEqual(viewModel.overlayState, .peek)

        viewModel.closeOneLevel()
        XCTAssertEqual(viewModel.overlayState, .hidden)

        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 1),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: false
        )
        XCTAssertEqual(viewModel.overlayState, .armed)
        viewModel.toggleExpand()
        XCTAssertEqual(viewModel.overlayState, .expand)
    }

    // MARK: - Fix A: Drag session must survive a momentary ineligible sample

    func testDragSessionRemainsActiveAcrossIneligibleSampleWhileStillDragging() async {
        let viewModel = makeViewModel()

        // Establish a drag session inside the trigger
        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: true
        )
        XCTAssertTrue(viewModel.isDragSessionActive)

        // Pointer momentarily outside trigger/capsule while drag is still in progress
        viewModel.ingestPointerSample(
            DropTelemetry(point: CGPoint(x: 500, y: 500), velocity: .zero, timestamp: 0.1),
            isTriggerRawInside: false,
            isTriggerOuterInside: false,
            isCapsuleInside: false,
            isDragging: true
        )

        // Session must survive — endDragSession is only called when !isDragging
        XCTAssertTrue(viewModel.isDragSessionActive, "Drag session must remain active while isDragging is true")
    }

    // MARK: - Fix C: Ending a drag while expanded must collapse the overlay to peek

    func testEndDragSessionCollapseExpandToPeek() async {
        let viewModel = makeViewModel()

        // Drag inside trigger expands the hub
        viewModel.ingestPointerSample(
            DropTelemetry(point: .zero, velocity: .zero, timestamp: 0),
            isTriggerRawInside: true,
            isTriggerOuterInside: true,
            isCapsuleInside: false,
            isDragging: true
        )
        XCTAssertEqual(viewModel.overlayState, .expand)
        XCTAssertTrue(viewModel.isDragSessionActive)

        // User releases the drag without dropping — hub must collapse to peek
        viewModel.endDragSession()

        XCTAssertEqual(viewModel.overlayState, .peek, "Overlay must collapse to peek when drag ends in expand state")
        XCTAssertFalse(viewModel.isDragSessionActive)
    }

    private func makeViewModel() -> NotchDockViewModel {
        NotchDockViewModel(
            actionService: DummyActionService(),
            dropRouting: DropRoutingEngine(),
            triggerEngine: TriggerEngine(enterDelay: 0.035, exitDelay: 0.1)
        )
    }
}

private final class DummyActionService: WorkActionExecuting {
    func classify(_ inputs: [URL]) -> DropPlan {
        _ = inputs
        return DropPlan(kind: .unsupported, recommendedAction: .sendToWorkbench, secondaryActions: [])
    }

    func execute(_ action: WorkActionKind, inputs: [URL]) async throws -> DropExecutionResult {
        _ = inputs
        return DropExecutionResult(
            action: action,
            outputs: [],
            reclaimedBytes: 0,
            undoToken: nil,
            message: "ok",
            warnings: []
        )
    }

    func undo(_ token: UndoToken) async -> Bool {
        _ = token
        return true
    }

    func unavailableReason(for action: WorkActionKind) -> String? {
        _ = action
        return nil
    }
}
