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

        XCTAssertNil(viewModel.targetedAction)
        XCTAssertEqual(viewModel.dropHubState, .idle)
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

    private func makeViewModel() -> NotchDockViewModel {
        NotchDockViewModel(
            iconSource: DummyIconSource(),
            actionService: DummyActionService(),
            iconPolicy: IconPolicyEngine(),
            dropRouting: DropRoutingEngine(),
            triggerEngine: TriggerEngine(enterDelay: 0.035, exitDelay: 0.1)
        )
    }
}

private final class DummyIconSource: IconSourceProviding {
    func fetchPinnedCandidates() async -> [DockIcon] { [] }
    func fetchUserSelectedIcons() async -> [DockIcon] { [] }
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
