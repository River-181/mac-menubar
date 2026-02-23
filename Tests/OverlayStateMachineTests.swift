import XCTest
@testable import NotchDock

@MainActor
final class OverlayStateMachineTests: XCTestCase {
    func testCoreStateTransitions() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .idle

        viewModel.transition(.topTriggerEnter)
        XCTAssertEqual(viewModel.overlayState, .peek)

        viewModel.transition(.capsuleClick)
        XCTAssertEqual(viewModel.overlayState, .expand)

        viewModel.transition(.stage2(.hotkey))
        XCTAssertEqual(viewModel.overlayState, .workspace)

        viewModel.transition(.closeOneLevel)
        XCTAssertEqual(viewModel.overlayState, .expand)
        viewModel.transition(.closeOneLevel)
        XCTAssertEqual(viewModel.overlayState, .peek)
        viewModel.transition(.closeOneLevel)
        XCTAssertEqual(viewModel.overlayState, .idle)
    }

    func testLeaveGraceCollapsesExpandToPeek() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .expand
        viewModel.setPointerInsideOverlay(false)
        viewModel.transition(.topTriggerExit)

        let expectation = expectation(description: "grace collapse")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            XCTAssertEqual(viewModel.overlayState, .peek)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.2)
    }

    func testDwellEntersWorkspaceFromPeek() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .peek
        viewModel.transition(.topTriggerEnter)

        let expectation = expectation(description: "dwell stage2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            XCTAssertEqual(viewModel.overlayState, .workspace)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testDragNearTopPromotesPeekToExpand() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .idle
        viewModel.setTopTrigger(isInside: true, pointer: .zero, timestamp: 0)
        XCTAssertEqual(viewModel.overlayState, .peek)

        viewModel.setDragActive(true, pointer: .zero, timestamp: 0)
        XCTAssertEqual(viewModel.overlayState, .expand)
    }

    func testDragHoverStage2EntersWorkspace() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .peek
        viewModel.setTopTrigger(isInside: true, pointer: .zero, timestamp: 0)
        viewModel.setDragActive(true, pointer: .zero, timestamp: 0)

        let expectation = expectation(description: "drag hover stage2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(viewModel.overlayState, .workspace)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testGroupCycleAppliesAndClearsGroupFilter() async {
        let icons = [
            DockIcon(id: "1", source: .manual, symbolOrImage: "wifi", title: "Wi-Fi", bucket: .pinned, groupID: "Network", lastUsedAt: .now, rank: 1),
            DockIcon(id: "2", source: .manual, symbolOrImage: "speaker", title: "Audio", bucket: .shelf, groupID: "Audio", lastUsedAt: .now, rank: 1)
        ]
        let viewModel = makeViewModel(icons: icons)
        await viewModel.refreshIcons()

        viewModel.focusNextGroup()
        XCTAssertNotNil(viewModel.activeGroupFilter)

        viewModel.focusPreviousGroup()
        XCTAssertNil(viewModel.activeGroupFilter)
    }

    func testSendToWorkbenchAppendsWorkspaceCards() async {
        let workspaceStore = TestWorkspaceStore()
        let workService = TestWorkActionService()
        let output = URL(fileURLWithPath: "/tmp/notchdock-test-output-\(UUID().uuidString).txt")
        workService.plan = DropPlan(kind: .mixed, recommendedAction: .sendToWorkbench, secondaryActions: [])
        workService.executionResult = ActionExecutionResult(
            action: .sendToWorkbench,
            outputs: [output],
            reclaimedBytes: 0,
            message: "Moved to Workbench: 1 file(s)",
            undoToken: nil,
            warnings: []
        )

        let viewModel = NotchDockViewModel(
            defaults: UserDefaults(suiteName: "tests.notchdock.workspace.\(UUID().uuidString)")!,
            iconSource: TestIconSource(),
            workActionService: workService,
            geometry: TestGeometry(),
            iconDockService: IconDockService(),
            workspaceStore: workspaceStore,
            externalProvider: nil
        )

        await viewModel.performDrop(inputs: [output], target: .sendToWorkbench)

        XCTAssertEqual(viewModel.workspaceCards.count, 1)
        XCTAssertEqual(viewModel.workspaceCards.first?.title, output.lastPathComponent)
        XCTAssertEqual(workspaceStore.state.cards.count, 1)
    }

    func testTriggerHysteresisRequiresEnterDelay() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .idle

        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.00),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: false
        )
        XCTAssertEqual(viewModel.triggerState, .entering)
        XCTAssertEqual(viewModel.overlayState, .idle)

        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.03),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: false
        )
        XCTAssertEqual(viewModel.triggerState, .entering)
        XCTAssertEqual(viewModel.overlayState, .idle)

        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.06),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: false
        )
        XCTAssertEqual(viewModel.triggerState, .inside)
        XCTAssertEqual(viewModel.overlayState, .peek)
    }

    func testDragSessionDoesNotSpamStateTransitions() async {
        let viewModel = makeViewModel()
        viewModel.overlayState = .idle

        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.00),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: true
        )
        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.06),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: true
        )
        viewModel.ingestPointerSample(
            DragTelemetry(point: .zero, velocity: .zero, timestamp: 0.12),
            isTriggerRawInside: true,
            isCapsuleInside: false,
            isDragging: true
        )

        XCTAssertEqual(viewModel.overlayState, .expand)
        XCTAssertEqual(viewModel.perfSnapshot.stateTransitions, 2)
    }

    func testDragTelemetrySetsAndClearsMagnetTargetAction() async {
        let workService = TestWorkActionService()
        workService.plan = DropPlan(kind: .images, recommendedAction: .optimizeImages, secondaryActions: [.compressZip])
        let viewModel = NotchDockViewModel(
            defaults: UserDefaults(suiteName: "tests.notchdock.magnet.\(UUID().uuidString)")!,
            iconSource: TestIconSource(),
            workActionService: workService,
            geometry: TestGeometry(),
            iconDockService: IconDockService(),
            workspaceStore: TestWorkspaceStore(),
            externalProvider: nil
        )

        viewModel.overlayState = .expand
        viewModel.dropPlan = DropPlan(kind: .images, recommendedAction: .optimizeImages, secondaryActions: [.compressZip])

        viewModel.ingestPointerSample(
            DragTelemetry(point: CGPoint(x: 100, y: 100), velocity: CGVector(dx: 320, dy: 0), timestamp: 1.0),
            isTriggerRawInside: true,
            isCapsuleInside: true,
            isDragging: true
        )
        XCTAssertEqual(viewModel.targetedDropAction, .optimizeImages)

        viewModel.endDragSession()
        XCTAssertNil(viewModel.targetedDropAction)
    }

    private func makeViewModel(icons: [DockIcon] = []) -> NotchDockViewModel {
        NotchDockViewModel(
            defaults: UserDefaults(suiteName: "tests.notchdock.overlay.\(UUID().uuidString)")!,
            iconSource: TestIconSource(icons: icons),
            workActionService: TestWorkActionService(),
            geometry: TestGeometry(),
            iconDockService: IconDockService(),
            workspaceStore: TestWorkspaceStore(),
            externalProvider: nil
        )
    }
}
