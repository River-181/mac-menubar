import AppKit
import Foundation
import SwiftUI

@MainActor
final class NotchDockViewModel: ObservableObject {
    static let shared = NotchDockViewModel()

    @Published private(set) var overlayState: OverlayState = .hidden
    @Published private(set) var dropHubState: DropHubState = .idle
    @Published private(set) var triggerState: TriggerState = .outside
    @Published private(set) var visibleIcons: [DockIcon] = []
    @Published private(set) var overflowIcons: [DockIcon] = []
    @Published private(set) var candidateIcons: [DockIcon] = []
    @Published private(set) var selectedIconIDs: Set<String> = []
    @Published var dropPlan = DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
    @Published var toast: OverlayToast?
    @Published var targetedAction: WorkActionKind?
    @Published private(set) var perfSnapshot: OverlayPerfSnapshot = .empty
    @Published private(set) var isDragSessionActive = false
    @Published private(set) var isNearTopTrigger = false
    @Published private(set) var isPointerInsideOverlay = false

    private let iconSource: IconSourceProviding
    private let actionService: WorkActionExecuting
    private let iconPolicy: IconPolicyProviding
    private let dropRouting: DropRoutingProviding
    private let stateMachine = OverlayStateMachine()
    private let triggerEngine: TriggerProviding

    private var allSelectedIcons: [DockIcon] = []
    private var leaveGraceWorkItem: DispatchWorkItem?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var hoverLockWorkItem: DispatchWorkItem?
    private var lastUndoToken: UndoToken?
    private var lastTriggerEnterTimestamp: TimeInterval?
    private var dragFrameAccumulatedMs: Double = 0
    private var dragFrameCount: Int = 0
    private var lastDragSampleTimestamp: TimeInterval?

    init(
        iconSource: IconSourceProviding = IconSourceService(),
        actionService: WorkActionExecuting = WorkActionService(),
        iconPolicy: IconPolicyProviding = IconPolicyEngine(),
        dropRouting: DropRoutingProviding = DropRoutingEngine(),
        triggerEngine: TriggerProviding = TriggerEngine()
    ) {
        self.iconSource = iconSource
        self.actionService = actionService
        self.iconPolicy = iconPolicy
        self.dropRouting = dropRouting
        self.triggerEngine = triggerEngine
        Task { await refreshIcons() }
    }

    var canUndoDangerousAction: Bool {
        guard let lastUndoToken else { return false }
        return Date() <= lastUndoToken.expiresAt
    }

    func transition(_ event: OverlayEvent) {
        let next = stateMachine.reduce(state: overlayState, event: event, isDragging: isDragSessionActive)
        guard next != overlayState else { return }
        withAnimation(animationForTransition(from: overlayState, to: next)) {
            overlayState = next
        }
        recomputeIconLayout()
    }

    func ingestPointerSample(
        _ sample: DropTelemetry,
        isTriggerRawInside: Bool,
        isTriggerOuterInside: Bool,
        isCapsuleInside: Bool,
        isDragging: Bool
    ) {
        isPointerInsideOverlay = isCapsuleInside
        if isTriggerRawInside && overlayState == .hidden {
            overlayState = .armed
        } else if !isTriggerRawInside && overlayState == .armed && !isDragging {
            overlayState = .hidden
        }
        isNearTopTrigger = isTriggerRawInside

        if let event = triggerEngine.update(rawInside: isTriggerRawInside, timestamp: sample.timestamp) {
            triggerState = triggerEngine.state
            recordTriggerEvent(event, timestamp: sample.timestamp)
            transition(event)
        } else {
            triggerState = triggerEngine.state
        }

        let isActivationTrigger = isTriggerRawInside || (isTriggerOuterInside && overlayState != .hidden)
        let shouldDriveDragSession = isDragging && (isDragSessionActive || isCapsuleInside || isActivationTrigger)

        if shouldDriveDragSession {
            if let previous = lastDragSampleTimestamp {
                let frameMs = max(0, (sample.timestamp - previous) * 1000)
                recordDragFrame(frameMs)
            }
            lastDragSampleTimestamp = sample.timestamp
            beginDragSession()
            if overlayState != .expand && overlayState != .processing {
                transition(.dragBegan)
            }
            updateTargetAction(with: sample)
        } else {
            lastDragSampleTimestamp = nil
            if !isDragging {
                endDragSession()
            }
        }

        if !isPointerInsideOverlay && !isNearTopTrigger && !isDragSessionActive {
            scheduleLeaveGrace()
        } else {
            cancelLeaveGrace()
        }
    }

    func beginDragSession() {
        guard !isDragSessionActive else { return }
        isDragSessionActive = true
        dropHubState = .predrag
    }

    func endDragSession() {
        guard isDragSessionActive else { return }
        isDragSessionActive = false
        targetedAction = nil
        hoverLockWorkItem?.cancel()
        hoverLockWorkItem = nil
        if overlayState == .processing {
            transition(.dragEnded)
        }
        if case .targeting = dropHubState {
            dropHubState = .idle
        }
    }

    func toggleExpand() {
        switch overlayState {
        case .hidden, .armed, .peek:
            transition(.clickCapsule)
        case .expand:
            transition(.esc)
        case .processing:
            break
        }
    }

    func closeOneLevel() {
        transition(.esc)
    }

    func setIconEnabled(_ iconID: String, enabled: Bool) {
        (iconSource as? IconSourceService)?.setEnabled(iconID, enabled: enabled)
        Task { await refreshIcons() }
    }

    func refreshIcons() async {
        let candidates = await iconSource.fetchPinnedCandidates()
        let selected = await iconSource.fetchUserSelectedIcons()
        candidateIcons = candidates
        allSelectedIcons = selected
        selectedIconIDs = Set(selected.map(\.id))
        recomputeIconLayout()
    }

    func performDrop(inputs: [URL], target: WorkActionKind?) async {
        dropPlan = actionService.classify(inputs)
        guard let action = dropRouting.resolveAction(plan: dropPlan, targeted: target ?? targetedAction, telemetry: nil) else {
            showToast("No available action for dropped files.", isError: true)
            return
        }

        transition(.dropCommitted)
        dropHubState = .processing

        do {
            let result = try await actionService.execute(action, inputs: inputs)
            lastUndoToken = result.undoToken
            dropHubState = .success
            showToast(result.message, isError: false)
        } catch {
            dropHubState = .failure
            showToast((error as? LocalizedError)?.errorDescription ?? "Action failed.", isError: true)
        }

        transition(.dragEnded)
    }

    func performActionFromPicker(_ action: WorkActionKind) async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Run \(action.title)"
        if panel.runModal() == .OK {
            await performDrop(inputs: panel.urls, target: action)
        }
    }

    func undoLastDangerousAction() async {
        guard let token = lastUndoToken else {
            showToast("Nothing to undo.", isError: true)
            return
        }
        guard Date() <= token.expiresAt else {
            showToast("Undo expired.", isError: true)
            lastUndoToken = nil
            return
        }
        if await actionService.undo(token) {
            lastUndoToken = nil
            showToast("Undo complete.", isError: false)
        } else {
            showToast("Undo failed.", isError: true)
        }
    }

    func updateIdleCPU(percent: Double) {
        perfSnapshot.idleCPUPercent = max(0, min(percent, 100))
    }

    func resetPerfSnapshot() {
        perfSnapshot = .empty
        lastTriggerEnterTimestamp = nil
        dragFrameAccumulatedMs = 0
        dragFrameCount = 0
        lastDragSampleTimestamp = nil
    }

    var perfSummaryText: String {
        String(
            format: "CPU %.2f%% · flap %d · drag %.2fms",
            perfSnapshot.idleCPUPercent,
            perfSnapshot.triggerFlaps,
            perfSnapshot.avgDragFrameMs
        )
    }

    private func updateTargetAction(with sample: DropTelemetry) {
        let resolved = dropRouting.resolveAction(plan: dropPlan, targeted: targetedAction, telemetry: sample)
        guard let resolved else {
            targetedAction = nil
            dropHubState = .predrag
            return
        }
        if targetedAction == resolved {
            return
        }
        targetedAction = resolved
        hoverLockWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.targetedAction == resolved {
                self.dropHubState = .targeting(resolved)
            }
        }
        hoverLockWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }

    private func recomputeIconLayout() {
        let arranged = iconPolicy.arrange(icons: allSelectedIcons, state: overlayState)
        visibleIcons = arranged.visible
        overflowIcons = arranged.overflow
    }

    private func scheduleLeaveGrace() {
        guard !isDragSessionActive else { return }
        guard overlayState == .peek || overlayState == .expand else { return }
        cancelLeaveGrace()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInsideOverlay, !self.isNearTopTrigger, !self.isDragSessionActive else { return }
            self.overlayState = .hidden
            self.dropHubState = .idle
            self.recomputeIconLayout()
        }
        leaveGraceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelLeaveGrace() {
        leaveGraceWorkItem?.cancel()
        leaveGraceWorkItem = nil
    }

    private func showToast(_ message: String, isError: Bool) {
        toastDismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.20)) {
            toast = OverlayToast(message: message, isError: isError)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.16)) {
                self?.toast = nil
            }
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func recordTriggerEvent(_ event: OverlayEvent, timestamp: TimeInterval) {
        switch event {
        case .pointerEnterTrigger:
            lastTriggerEnterTimestamp = timestamp
        case .pointerExitTrigger:
            if let enter = lastTriggerEnterTimestamp, (timestamp - enter) <= 0.22 {
                perfSnapshot.triggerFlaps += 1
            }
            lastTriggerEnterTimestamp = nil
        default:
            break
        }
    }

    private func recordDragFrame(_ frameMs: Double) {
        dragFrameAccumulatedMs += frameMs
        dragFrameCount += 1
        perfSnapshot.dragSampleCount = dragFrameCount
        perfSnapshot.avgDragFrameMs = dragFrameAccumulatedMs / Double(max(1, dragFrameCount))
    }

    private func animationForTransition(from: OverlayState, to: OverlayState) -> Animation {
        switch (from, to) {
        case (.hidden, .armed), (.armed, .peek), (.hidden, .peek):
            return .interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1)
        case (_, .expand):
            return .interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.1)
        case (_, .hidden):
            return .easeOut(duration: 0.14)
        default:
            return .interactiveSpring(response: 0.26, dampingFraction: 0.86, blendDuration: 0.1)
        }
    }
}
