import AppKit
import Foundation
import SwiftUI

@MainActor
final class NotchDockViewModel: ObservableObject {
    static let shared = NotchDockViewModel()

    @Published private(set) var overlayState: OverlayState = .hidden
    @Published private(set) var presentationState: OverlayState = .hidden
    @Published private(set) var dropHubState: DropHubState = .idle
    @Published private(set) var triggerState: TriggerState = .outside
    @Published private(set) var visibleIcons: [DockIcon] = []
    @Published private(set) var overflowIcons: [DockIcon] = []
    @Published private(set) var candidateIcons: [DockIcon] = []
    @Published private(set) var selectedIconIDs: Set<String> = []
    @Published private(set) var interactionMode: OverlayInteractionMode = .click
    @Published private(set) var panelSize: CGSize = OverlayState.armed.panelSize
    @Published private(set) var presentedActions: [WorkActionKind] = []
    @Published private(set) var actionDisabledReasons: [WorkActionKind: String] = [:]
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
        refreshPresentation()
        Task { await refreshIcons() }
    }

    var canUndoDangerousAction: Bool {
        guard let lastUndoToken else { return false }
        return Date() <= lastUndoToken.expiresAt
    }

    var isRecommendedActionVisible: Bool {
        targetedAction == nil
    }

    func transition(_ event: OverlayEvent) {
        let next = stateMachine.reduce(state: overlayState, event: event, isDragging: isDragSessionActive)
        guard next != overlayState else { return }
        withAnimation(animationForTransition(from: overlayState, to: next)) {
            overlayState = next
        }
        recomputeIconLayout()
        refreshPresentation()
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
            refreshPresentation()
        } else if !isTriggerRawInside && overlayState == .armed && !isDragging {
            overlayState = .hidden
            refreshPresentation()
        }
        isNearTopTrigger = isTriggerRawInside

        if let event = triggerEngine.update(rawInside: isTriggerRawInside, timestamp: sample.timestamp) {
            triggerState = triggerEngine.state
            recordTriggerEvent(event, timestamp: sample.timestamp)
            transition(event)
        } else {
            triggerState = triggerEngine.state
        }

        interactionMode = isDragging ? .drag : .click
        let isDragEligible = isTriggerRawInside || isCapsuleInside
        let shouldDriveDragSession = isDragging && (isDragEligible || (isDragSessionActive && isCapsuleInside))

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
            updateDropPresentation(isTriggerRawInside: isTriggerRawInside, isCapsuleInside: isCapsuleInside)
        } else {
            lastDragSampleTimestamp = nil
            if isDragSessionActive {
                clearTargetAction()
            }
            if isDragging {
                endDragSession()
            } else {
                endDragSession()
            }
        }

        if !isPointerInsideOverlay && !isNearTopTrigger && !isDragSessionActive {
            scheduleLeaveGrace()
        } else {
            cancelLeaveGrace()
        }
        refreshPresentation()
    }

    func beginDragSession() {
        guard !isDragSessionActive else { return }
        isDragSessionActive = true
        interactionMode = .drag
        dropHubState = .preview
        refreshPresentation()
    }

    func endDragSession() {
        guard isDragSessionActive else { return }
        isDragSessionActive = false
        interactionMode = .click
        clearTargetAction()
        if overlayState == .processing {
            transition(.dragEnded)
        }
        if case .focused = dropHubState {
            dropHubState = .idle
        }
        if dropHubState == .preview {
            dropHubState = .idle
        }
        refreshPresentation()
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
        refreshPresentation()
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

    func setHoveredAction(_ action: WorkActionKind?) {
        if let action {
            guard targetedAction != action else { return }
            targetedAction = action
            hoverLockWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.targetedAction == action {
                    self.dropHubState = .focused(action)
                    self.refreshPresentation()
                }
            }
            hoverLockWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            return
        }
        clearTargetAction()
        if isDragSessionActive {
            dropHubState = .preview
        }
        refreshPresentation()
    }

    func performActionFromPicker(_ action: WorkActionKind) async {
        if let reason = actionDisabledReasons[action] {
            showToast(reason, isError: true)
            return
        }
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

    private func updateDropPresentation(isTriggerRawInside: Bool, isCapsuleInside: Bool) {
        guard isTriggerRawInside || isCapsuleInside else {
            clearTargetAction()
            if isDragSessionActive {
                dropHubState = .preview
            }
            return
        }
        if targetedAction == nil {
            dropHubState = .preview
        }
    }

    private func clearTargetAction() {
        targetedAction = nil
        hoverLockWorkItem?.cancel()
        hoverLockWorkItem = nil
    }

    private func recomputeIconLayout() {
        let arranged = iconPolicy.arrange(icons: allSelectedIcons, state: overlayState)
        visibleIcons = arranged.visible
        overflowIcons = arranged.overflow
        refreshPresentation()
    }

    private func refreshPresentation() {
        let nextState = resolvedPresentationState()
        if presentationState != nextState {
            presentationState = nextState
        }
        let nextActions = resolvedPresentedActions()
        if presentedActions != nextActions {
            presentedActions = nextActions
        }
        let nextDisabledReasons = Dictionary(uniqueKeysWithValues: WorkActionKind.allCases.compactMap { action in
            actionService.unavailableReason(for: action).map { (action, $0) }
        })
        if actionDisabledReasons != nextDisabledReasons {
            actionDisabledReasons = nextDisabledReasons
        }
        let nextPanelSize = resolvedPanelSize(for: nextState)
        if panelSize != nextPanelSize {
            panelSize = nextPanelSize
        }
    }

    private func resolvedPresentationState() -> OverlayState {
        if overlayState == .hidden && (isNearTopTrigger || triggerState == .entering) {
            return .armed
        }
        return overlayState
    }

    private func resolvedPanelSize(for state: OverlayState) -> CGSize {
        guard state != .hidden else {
            return CGSize(width: 30, height: 30)
        }

        let width = state.capsuleSize.width + 16
        let verticalPadding: CGFloat = 16
        let toastHeight: CGFloat = toast == nil ? 0 : 52

        switch state {
        case .armed:
            return CGSize(width: width, height: 58)
        case .peek:
            let iconHeight: CGFloat = visibleIcons.isEmpty ? 0 : 44
            let hintHeight: CGFloat = isDragSessionActive ? 0 : 24
            return CGSize(width: width, height: verticalPadding + iconHeight + hintHeight + toastHeight + 12)
        case .expand, .processing:
            let iconHeight: CGFloat = visibleIcons.isEmpty ? 0 : 44
            let headerHeight: CGFloat = 32
            let hubHeaderHeight: CGFloat = 22
            let columns: CGFloat = interactionMode == .drag ? 3 : 2
            let actionCount = CGFloat(max(1, presentedActions.count))
            let rows = ceil(actionCount / columns)
            let chipHeight = rows * 68
            let totalHeight = verticalPadding + headerHeight + iconHeight + hubHeaderHeight + chipHeight + toastHeight + 34
            return CGSize(width: width, height: totalHeight)
        case .hidden:
            return CGSize(width: 30, height: 30)
        }
    }

    private var dropActions: [WorkActionKind] {
        let primary = dropPlan.recommendedAction.map { [$0] } ?? []
        let merged = primary + dropPlan.secondaryActions
        return merged.isEmpty ? WorkActionKind.allCases : merged
    }

    private func resolvedPresentedActions() -> [WorkActionKind] {
        if interactionMode == .click {
            return WorkActionKind.allCases
        }
        let source = dropActions
        guard let recommended = dropPlan.recommendedAction else {
            return Array(source.prefix(6))
        }
        let peers = source.filter { $0.category == recommended.category && $0 != recommended }
        let organize = source.filter { $0.category == .organize }
        return Array(([recommended] + peers.prefix(2) + organize.prefix(1)).uniqued())
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
            self.refreshPresentation()
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
            self?.refreshPresentation()
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        refreshPresentation()
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

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
