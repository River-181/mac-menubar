import AppKit
import Foundation
import SwiftUI

@MainActor
final class NotchDockViewModel: ObservableObject {
    static let shared: NotchDockViewModel = {
        let ax = AXIconSourceService()
        return NotchDockViewModel(
            iconSource: CompositeIconSourceService(ax: ax, axProvider: ax),
            externalProvider: ax
        )
    }()

    @Published var overlayState: DockOverlayState = .idle
    @Published var notchDefaultPolicy: NotchDefaultPolicy = .adaptiveAuto
    @Published var workHubStyle: WorkHubStyle = .magneticDock
    @Published var reduceMotionEnabled = false
    @Published var enableInteractiveMagnet = true
    @Published var showRunningAppIcons = false

    @Published var isPointerInsideOverlay = false
    @Published var isNearTopTrigger = false
    @Published private(set) var triggerState: TriggerState = .outside
    @Published private(set) var dragTelemetry: DragTelemetry?
    @Published private(set) var perfSnapshot: OverlayPerfSnapshot = .empty
    @Published var effectiveCompactMode = true
    @Published var effectiveSpacing: CGFloat = 8

    @Published var pinnedIcons: [DockIcon] = []
    @Published var shelfIcons: [DockIcon] = []
    @Published private(set) var overflowIcons: [DockIcon] = []
    @Published private(set) var groupedVisibleIcons: [String: [DockIcon]] = [:]
    @Published var visibleIcons: [DockIcon] = []
    @Published var focusedIconID: String?
    @Published private(set) var activeGroupFilter: String?
    @Published var searchQuery = ""

    @Published var dropPlan = DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
    @Published private(set) var targetedDropAction: WorkActionKind?
    @Published var dropToast: DropToast?
    @Published var isDropProcessing = false
    @Published private(set) var isDragSessionActive = false
    @Published var externalAuthState: MirrorAuthState = .unknown
    @Published private(set) var workspaceCards: [WorkspaceCard] = []
    @Published private(set) var workspaceClusters: [WorkspaceCluster] = []

    private let defaults: UserDefaults
    private let iconSource: IconSourceProviding
    private let workActionService: WorkActionExecuting
    private let geometry: NotchGeometryCalculating
    private let iconDockService: IconDockService
    private let workspaceStore: WorkspaceStoring
    private let externalProvider: ExternalIconProviding?

    private let policyKey = "notchdock.policy.v1"
    private let magnetKey = "notchdock.magnet.v1"
    private let reduceMotionKey = "notchdock.reduce-motion.v1"
    private let runningAppsKey = "notchdock.running-app-icons.v1"

    private var leaveGraceWorkItem: DispatchWorkItem?
    private var dwellStage2WorkItem: DispatchWorkItem?
    private var preheatExpandWorkItem: DispatchWorkItem?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var dragStage2WorkItem: DispatchWorkItem?
    private var lastUndoToken: UndoToken?
    private var workspaceState: WorkspaceState
    private var triggerEnterStartedAt: TimeInterval?
    private var triggerExitStartedAt: TimeInterval?
    private var lastStableTriggerChangeAt: TimeInterval?
    private var dragFrameCount = 0
    private var dragFrameTotalMs: Double = 0
    private var lastDragSampleTimestamp: TimeInterval?

    private let triggerEnterDelay: TimeInterval = 0.05
    private let triggerExitDelay: TimeInterval = 0.12

    init(
        defaults: UserDefaults = .standard,
        iconSource: IconSourceProviding = ManualIconSourceService(),
        workActionService: WorkActionExecuting = WorkActionService(),
        geometry: NotchGeometryCalculating = NotchGeometryCalculator(),
        iconDockService: IconDockService = IconDockService(),
        workspaceStore: WorkspaceStoring = WorkspaceStore(),
        externalProvider: ExternalIconProviding? = nil
    ) {
        self.defaults = defaults
        self.iconSource = iconSource
        self.workActionService = workActionService
        self.geometry = geometry
        self.iconDockService = iconDockService
        self.workspaceStore = workspaceStore
        self.externalProvider = externalProvider
        self.workspaceState = workspaceStore.load()
        publishWorkspaceState()
        loadPreferences()
        syncRunningAppsPreference()
        Task { await refreshIcons() }
    }

    var canUndoDangerousAction: Bool {
        guard let token = lastUndoToken else { return false }
        return Date() <= token.expiresAt
    }

    func transition(_ event: OverlayEvent) {
        switch event {
        case .topTriggerEnter:
            isNearTopTrigger = true
            triggerState = .inside
            triggerEnterStartedAt = nil
            cancelLeaveGrace()
            if overlayState == .idle {
                animateStateChange(to: .peek)
                schedulePreheatExpand()
            }
            if overlayState == .peek && isDragSessionActive {
                animateStateChange(to: .expand)
            }
            if isDragSessionActive {
                scheduleDragStage2IfNeeded()
            }
            scheduleStage2DwellIfNeeded()

        case .topTriggerExit:
            isNearTopTrigger = false
            triggerState = .outside
            triggerExitStartedAt = nil
            cancelPreheatExpand()
            cancelStage2Dwell()
            cancelDragStage2()
            if !isPointerInsideOverlay, overlayState == .peek {
                animateStateChange(to: .idle)
            }

        case .capsuleClick:
            switch overlayState {
            case .idle, .peek:
                animateStateChange(to: .expand)
            case .expand, .grab, .focus:
                animateStateChange(to: .peek)
            case .workspace:
                animateStateChange(to: .expand)
            }

        case .pointerLeave:
            isPointerInsideOverlay = false
            scheduleLeaveGrace()

        case .pointerReturn:
            isPointerInsideOverlay = true
            cancelLeaveGrace()

        case .stage2:
            if overlayState == .peek || overlayState == .expand {
                animateStateChange(to: .workspace)
            }

        case .closeOneLevel:
            switch overlayState {
            case .workspace:
                animateStateChange(to: .expand)
            case .focus, .grab:
                animateStateChange(to: .expand)
            case .expand:
                animateStateChange(to: .peek)
            case .peek:
                animateStateChange(to: .idle)
            case .idle:
                break
            }

        case .longPressIcon(let iconID):
            focusedIconID = iconID
            animateStateChange(to: .grab)

        case .focusIcon(let iconID):
            focusedIconID = iconID
            animateStateChange(to: .focus)

        case .closeFocus:
            focusedIconID = nil
            if overlayState == .focus || overlayState == .grab {
                animateStateChange(to: .expand)
            }
        }

        recomputeArrangement()
        syncExternalCadence()
    }

    func setTopTrigger(isInside: Bool, pointer: CGPoint, timestamp: TimeInterval) {
        _ = pointer
        _ = timestamp
        triggerState = isInside ? .inside : .outside
        triggerEnterStartedAt = nil
        triggerExitStartedAt = nil
        if isInside != isNearTopTrigger {
            transition(isInside ? .topTriggerEnter : .topTriggerExit)
        }
    }

    func setDragActive(_ active: Bool, pointer: CGPoint, timestamp: TimeInterval) {
        _ = pointer
        _ = timestamp
        if isDragSessionActive == active {
            syncExternalCadence()
            return
        }
        if active {
            beginDragSession()
        } else {
            endDragSession()
        }
        syncExternalCadence()
    }

    func ingestPointerSample(
        _ sample: DragTelemetry,
        isTriggerRawInside: Bool,
        isCapsuleInside: Bool,
        isDragging: Bool
    ) {
        dragTelemetry = sample
        setPointerInsideOverlay(isCapsuleInside)
        processTriggerState(rawInside: isTriggerRawInside, timestamp: sample.timestamp)
        if isDragging {
            beginDragSession()
            accumulateDragFrame(sample.timestamp)
        } else {
            endDragSession()
        }

        if isDragSessionActive, overlayState == .expand || overlayState == .grab || overlayState == .focus {
            targetedDropAction = chooseDropTarget(for: sample)
        } else {
            targetedDropAction = nil
        }
    }

    func beginDragSession() {
        guard !isDragSessionActive else { return }
        isDragSessionActive = true
        maybePromoteForDrag()
        scheduleDragStage2IfNeeded()
        syncExternalCadence()
    }

    func endDragSession() {
        guard isDragSessionActive else { return }
        isDragSessionActive = false
        cancelDragStage2()
        targetedDropAction = nil
        lastDragSampleTimestamp = nil
        syncExternalCadence()
    }

    func chooseDropTarget(for sample: DragTelemetry) -> WorkActionKind? {
        if let recommended = dropPlan.recommendedAction {
            return recommended
        }
        if dropPlan.secondaryActions.isEmpty {
            return WorkActionKind.allCases.first
        }
        return sample.velocity.dx >= 0 ? dropPlan.secondaryActions.first : dropPlan.secondaryActions.last
    }

    func updateIdleCPU(_ value: Double) {
        let clamped = max(0, min(100, value))
        perfSnapshot.idleCPU = clamped
    }

    func resetPerfSnapshot() {
        perfSnapshot = .empty
        dragFrameCount = 0
        dragFrameTotalMs = 0
        lastDragSampleTimestamp = nil
        lastStableTriggerChangeAt = nil
    }

    var perfSnapshotSummary: String {
        String(
            format: "idleCPU %.2f%% | flaps %d | drag %.2fms | transitions %d",
            perfSnapshot.idleCPU,
            perfSnapshot.triggerFlaps,
            perfSnapshot.avgDragFrameMs,
            perfSnapshot.stateTransitions
        )
    }

    func setPointerInsideOverlay(_ inside: Bool) {
        if inside == isPointerInsideOverlay {
            if !inside, overlayState != .idle, leaveGraceWorkItem == nil {
                scheduleLeaveGrace()
            }
            return
        }
        transition(inside ? .pointerReturn : .pointerLeave)
    }

    func toggleExpand() {
        transition(.capsuleClick)
    }

    func prepareDropPreview() {
        targetedDropAction = dropPlan.recommendedAction
        switch overlayState {
        case .idle:
            animateStateChange(to: .peek)
            animateStateChange(to: .expand)
        case .peek:
            animateStateChange(to: .expand)
        case .expand, .grab, .focus, .workspace:
            break
        }
        recomputeArrangement()
    }

    func toggleWorkspace(trigger: Stage2Trigger = .hotkey) {
        if overlayState == .workspace {
            animateStateChange(to: .expand)
        } else {
            transition(.stage2(trigger))
        }
        recomputeArrangement()
    }

    func closeOneLevel() {
        transition(.closeOneLevel)
    }

    func reorderIcon(_ iconID: String, before targetID: String) {
        guard let from = shelfIcons.firstIndex(where: { $0.id == iconID }),
              let to = shelfIcons.firstIndex(where: { $0.id == targetID }),
              from != to else {
            return
        }
        let icon = shelfIcons.remove(at: from)
        let target = from < to ? to - 1 : to
        shelfIcons.insert(icon, at: target)
        recomputeArrangement()
    }

    func markIconUsed(_ iconID: String) {
        if let index = pinnedIcons.firstIndex(where: { $0.id == iconID }) {
            pinnedIcons[index].lastUsedAt = .now
        }
        if let index = shelfIcons.firstIndex(where: { $0.id == iconID }) {
            shelfIcons[index].lastUsedAt = .now
        }
        recomputeArrangement()
    }

    func focusNextGroup() {
        let groups = groupedVisibleIcons.keys.sorted()
        guard !groups.isEmpty else {
            activeGroupFilter = nil
            return
        }
        if let activeGroupFilter,
           let index = groups.firstIndex(of: activeGroupFilter),
           index + 1 < groups.count {
            self.activeGroupFilter = groups[index + 1]
        } else if activeGroupFilter == groups.last {
            activeGroupFilter = nil
        } else {
            activeGroupFilter = groups.first
        }
        recomputeArrangement()
    }

    func focusPreviousGroup() {
        let groups = groupedVisibleIcons.keys.sorted()
        guard !groups.isEmpty else {
            activeGroupFilter = nil
            return
        }
        if let activeGroupFilter,
           let index = groups.firstIndex(of: activeGroupFilter),
           index > 0 {
            self.activeGroupFilter = groups[index - 1]
        } else if activeGroupFilter == groups.first {
            activeGroupFilter = nil
        } else {
            activeGroupFilter = groups.last
        }
        recomputeArrangement()
    }

    func setPolicy(_ policy: NotchDefaultPolicy) {
        notchDefaultPolicy = policy
        defaults.set(policy.rawValue, forKey: policyKey)
    }

    func setInteractiveMagnet(_ enabled: Bool) {
        enableInteractiveMagnet = enabled
        defaults.set(enabled, forKey: magnetKey)
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotionEnabled = enabled
        defaults.set(enabled, forKey: reduceMotionKey)
    }

    func setShowRunningAppIcons(_ enabled: Bool) {
        showRunningAppIcons = enabled
        defaults.set(enabled, forKey: runningAppsKey)
        syncRunningAppsPreference()
        Task { await refreshIcons() }
    }

    func applyPolicy(for screen: NSScreen, hasNotch: Bool) {
        switch notchDefaultPolicy {
        case .adaptiveAuto:
            effectiveCompactMode = hasNotch
        case .alwaysCompact:
            effectiveCompactMode = true
        case .alwaysRespect:
            effectiveCompactMode = false
        }
        effectiveSpacing = geometry.layoutSnapshot(screen: screen, policy: notchDefaultPolicy).spacing
    }

    func refreshLayout(for screen: NSScreen) {
        let snapshot = geometry.layoutSnapshot(screen: screen, policy: notchDefaultPolicy)
        applyPolicy(for: screen, hasNotch: snapshot.hasNotch)
    }

    func performDrop(inputs: [URL], target: WorkActionKind?) async {
        let plan = workActionService.classify(inputs)
        dropPlan = plan
        let resolvedAction = target ?? targetedDropAction ?? plan.recommendedAction ?? plan.secondaryActions.first
        guard let action = resolvedAction else {
            showToast("No valid action for dropped files.", isError: true)
            return
        }

        isDropProcessing = true
        defer { isDropProcessing = false }

        do {
            let result = try await executeDrop(action: action, inputs: inputs)
            if action == .sendToWorkbench {
                appendWorkspaceCards(from: result.outputs)
            }
            lastUndoToken = result.undoToken
            showToast(result.message, isError: false)
        } catch {
            showToast((error as? LocalizedError)?.errorDescription ?? "Action failed.", isError: true)
        }
    }

    func performActionFromPicker(_ action: WorkActionKind) async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Run \(action.displayName)"
        panel.message = "Choose files or folders to process."

        if panel.runModal() == .OK {
            await performDrop(inputs: panel.urls, target: action)
        }
    }

    func undoLastDangerousAction() async {
        guard let token = lastUndoToken else {
            showToast("Nothing to undo.", isError: true)
            return
        }
        guard canUndoDangerousAction else {
            showToast("Undo window expired.", isError: true)
            lastUndoToken = nil
            return
        }
        if workActionService.undo(token: token) {
            showToast("Undo completed.", isError: false)
            lastUndoToken = nil
        } else {
            showToast("Undo failed.", isError: true)
        }
    }

    func requestExternalPermission() {
        if let externalProvider {
            externalProvider.start()
            externalAuthState = externalProvider.authState
            return
        }
        externalAuthState = .unknown
    }

    func refreshExternalIcons() {
        externalProvider?.refresh()
        externalAuthState = externalProvider?.authState ?? .unknown
    }

    func refreshIcons() async {
        syncRunningAppsPreference()
        var icons = await iconSource.fetchIcons()
        if !showRunningAppIcons {
            icons.removeAll { $0.groupID == "Running Apps" }
        }
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let keyword = searchQuery.lowercased()
            icons = icons.filter { $0.title.lowercased().contains(keyword) || $0.groupID.lowercased().contains(keyword) }
        }
        pinnedIcons = icons.filter { $0.bucket == .pinned }
        shelfIcons = icons.filter { $0.bucket != .pinned }
        recomputeArrangement()
    }

    func openWorkspaceCard(_ cardID: String) {
        guard let card = workspaceCards.first(where: { $0.id == cardID }),
              let fileURL = card.fileURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func removeWorkspaceCard(_ cardID: String) {
        workspaceState.cards.removeAll { $0.id == cardID }
        workspaceState.updatedAt = .now
        publishWorkspaceState()
        persistWorkspaceState()
    }

    private func recomputeArrangement() {
        let arranged = iconDockService.arrange(pinned: pinnedIcons, shelf: shelfIcons, state: overlayState)
        if let activeGroupFilter, !activeGroupFilter.isEmpty {
            visibleIcons = arranged.visible.filter { $0.groupID == activeGroupFilter }
        } else {
            visibleIcons = arranged.visible
        }
        overflowIcons = arranged.overflow
        groupedVisibleIcons = arranged.grouped
    }

    private func scheduleStage2DwellIfNeeded() {
        cancelStage2Dwell()
        guard overlayState == .peek || overlayState == .expand else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isNearTopTrigger else { return }
            self.transition(.stage2(.dwell300ms))
        }
        dwellStage2WorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func schedulePreheatExpand() {
        cancelPreheatExpand()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isNearTopTrigger else { return }
            guard self.overlayState == .peek else { return }
            self.animateStateChange(to: .expand)
            self.recomputeArrangement()
        }
        preheatExpandWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func cancelPreheatExpand() {
        preheatExpandWorkItem?.cancel()
        preheatExpandWorkItem = nil
    }

    private func cancelStage2Dwell() {
        dwellStage2WorkItem?.cancel()
        dwellStage2WorkItem = nil
    }

    private func scheduleLeaveGrace() {
        cancelLeaveGrace()
        guard overlayState != .idle else { return }
        if overlayState == .workspace {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInsideOverlay && !self.isNearTopTrigger else { return }
            if self.overlayState == .peek {
                self.animateStateChange(to: .idle)
            } else {
                self.animateStateChange(to: .peek)
            }
            self.recomputeArrangement()
        }
        leaveGraceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func cancelLeaveGrace() {
        leaveGraceWorkItem?.cancel()
        leaveGraceWorkItem = nil
    }

    private func maybePromoteForDrag() {
        guard isNearTopTrigger else { return }
        switch overlayState {
        case .idle:
            animateStateChange(to: .peek)
        case .peek:
            animateStateChange(to: .expand)
        default:
            break
        }
        recomputeArrangement()
    }

    private func scheduleDragStage2IfNeeded() {
        cancelDragStage2()
        guard isDragSessionActive, isNearTopTrigger else { return }
        guard overlayState == .expand || overlayState == .peek else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isDragSessionActive, self.isNearTopTrigger else { return }
            self.transition(.stage2(.dragHover250ms))
        }
        dragStage2WorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelDragStage2() {
        dragStage2WorkItem?.cancel()
        dragStage2WorkItem = nil
    }

    private func showToast(_ message: String, isError: Bool) {
        toastDismissWorkItem?.cancel()
        dropToast = DropToast(message: message, isError: isError)
        let work = DispatchWorkItem { [weak self] in
            self?.dropToast = nil
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func animateStateChange(to next: DockOverlayState) {
        guard overlayState != next else { return }
        let current = overlayState
        perfSnapshot.stateTransitions += 1
        if reduceMotionEnabled {
            withAnimation(.easeInOut(duration: 0.12)) {
                overlayState = next
            }
            return
        }
        withAnimation(animationForTransition(from: current, to: next)) {
            overlayState = next
        }
    }

    private func animationForTransition(from: DockOverlayState, to: DockOverlayState) -> Animation {
        switch (from, to) {
        case (.idle, .peek):
            return .interactiveSpring(response: 0.26, dampingFraction: 0.86, blendDuration: 0.08)
        case (.peek, .expand):
            return .interactiveSpring(response: 0.30, dampingFraction: 0.84, blendDuration: 0.10)
        case (.peek, .workspace), (.expand, .workspace):
            return .interactiveSpring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.10)
        case (.focus, .expand), (.grab, .expand), (.expand, .peek):
            return .easeOut(duration: 0.14)
        case (.workspace, .expand), (.peek, .idle):
            return .interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.08)
        default:
            if isDragSessionActive {
                return .spring(response: 0.22, dampingFraction: 0.80, blendDuration: 0.08)
            }
            return .interactiveSpring(response: 0.30, dampingFraction: 0.84, blendDuration: 0.10)
        }
    }

    private func syncExternalCadence() {
        let active = isDragSessionActive || overlayState == .expand || overlayState == .workspace
        externalProvider?.setHighFrequencyMode(active)
    }

    private func executeDrop(action: WorkActionKind, inputs: [URL]) async throws -> ActionExecutionResult {
        let executor = AsyncDropExecutor(service: workActionService)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try executor.execute(action: action, inputs: inputs)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadPreferences() {
        if let raw = defaults.string(forKey: policyKey), let policy = NotchDefaultPolicy(rawValue: raw) {
            notchDefaultPolicy = policy
        }
        enableInteractiveMagnet = defaults.object(forKey: magnetKey) as? Bool ?? true
        reduceMotionEnabled = defaults.object(forKey: reduceMotionKey) as? Bool ?? false
        showRunningAppIcons = defaults.object(forKey: runningAppsKey) as? Bool ?? false
    }

    private func syncRunningAppsPreference() {
        (iconSource as? RunningAppIconControlling)?.setIncludeRunningApps(showRunningAppIcons)
    }

    private func processTriggerState(rawInside: Bool, timestamp: TimeInterval) {
        switch triggerState {
        case .outside:
            if rawInside {
                triggerState = .entering
                triggerEnterStartedAt = timestamp
            }

        case .entering:
            if rawInside {
                let elapsed = timestamp - (triggerEnterStartedAt ?? timestamp)
                if elapsed >= triggerEnterDelay {
                    triggerState = .inside
                    triggerEnterStartedAt = nil
                    markStableTriggerChange(at: timestamp)
                    if !isNearTopTrigger {
                        transition(.topTriggerEnter)
                    }
                }
            } else {
                triggerState = .outside
                triggerEnterStartedAt = nil
            }

        case .inside:
            if !rawInside {
                triggerState = .exiting
                triggerExitStartedAt = timestamp
            }

        case .exiting:
            if !rawInside {
                let elapsed = timestamp - (triggerExitStartedAt ?? timestamp)
                if elapsed >= triggerExitDelay {
                    triggerState = .outside
                    triggerExitStartedAt = nil
                    markStableTriggerChange(at: timestamp)
                    if isNearTopTrigger {
                        transition(.topTriggerExit)
                    }
                }
            } else {
                triggerState = .inside
                triggerExitStartedAt = nil
            }
        }
    }

    private func markStableTriggerChange(at timestamp: TimeInterval) {
        if let last = lastStableTriggerChangeAt, (timestamp - last) <= 0.8 {
            perfSnapshot.triggerFlaps += 1
        }
        lastStableTriggerChangeAt = timestamp
    }

    private func accumulateDragFrame(_ timestamp: TimeInterval) {
        defer { lastDragSampleTimestamp = timestamp }
        guard let previous = lastDragSampleTimestamp else { return }
        let deltaMs = (timestamp - previous) * 1000
        guard deltaMs > 0, deltaMs < 500 else { return }

        dragFrameCount += 1
        dragFrameTotalMs += deltaMs
        perfSnapshot.avgDragFrameMs = dragFrameTotalMs / Double(dragFrameCount)
    }

    private func publishWorkspaceState() {
        workspaceCards = workspaceState.cards
        workspaceClusters = workspaceState.clusters
    }

    private func appendWorkspaceCards(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        if workspaceState.clusters.isEmpty {
            workspaceState.clusters = [
                WorkspaceCluster(id: "workbench-default", name: "Workbench", colorHex: "#BFC7D5")
            ]
        }
        let clusterID = workspaceState.clusters[0].id
        let startIndex = workspaceState.cards.count
        let newCards: [WorkspaceCard] = urls.enumerated().map { offset, url in
            let index = startIndex + offset
            let column = index % 3
            let row = index / 3
            return WorkspaceCard(
                id: UUID().uuidString,
                title: url.lastPathComponent,
                fileURL: url,
                noteText: nil,
                positionX: Double(28 + (column * 220)),
                positionY: Double(28 + (row * 78)),
                clusterID: clusterID
            )
        }

        workspaceState.cards.append(contentsOf: newCards)
        if workspaceState.cards.count > 200 {
            workspaceState.cards = Array(workspaceState.cards.suffix(200))
        }
        workspaceState.updatedAt = .now
        publishWorkspaceState()
        persistWorkspaceState()
    }

    private func persistWorkspaceState() {
        do {
            try workspaceStore.save(workspaceState)
        } catch {
            showToast("Failed to save workspace state.", isError: true)
        }
    }
}

private final class AsyncDropExecutor: @unchecked Sendable {
    private let service: WorkActionExecuting

    init(service: WorkActionExecuting) {
        self.service = service
    }

    func execute(action: WorkActionKind, inputs: [URL]) throws -> ActionExecutionResult {
        try service.execute(action: action, inputs: inputs, outputPolicy: .datedFolder)
    }
}
