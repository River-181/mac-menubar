import AppKit
import Combine
import CoreGraphics
import Foundation

enum VisibilityGroup: String, Codable, CaseIterable, Identifiable {
    case alwaysVisible
    case smartHide
    case hidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alwaysVisible: return "Always Visible"
        case .smartHide: return "Smart Hide"
        case .hidden: return "Hidden"
        }
    }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum NotchDisplayMode: String, Codable, CaseIterable, Identifiable {
    case respectNotch
    case hideNotchLike

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .respectNotch:
            return "Respect Notch"
        case .hideNotchLike:
            return "Hide Notch (Compact)"
        }
    }
}

enum NotchDefaultPolicy: String, Codable, CaseIterable, Identifiable {
    case adaptiveAuto
    case alwaysCompact
    case alwaysRespect

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptiveAuto:
            return "Adaptive Auto"
        case .alwaysCompact:
            return "Always Compact"
        case .alwaysRespect:
            return "Always Respect"
        }
    }
}

enum WorkHubStyle: String, Codable, CaseIterable, Identifiable {
    case magneticDock

    var id: String { rawValue }

    var displayName: String {
        "Magnetic Chip Dock"
    }
}

struct MenuBarIcon: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var shortTitle: String
    var group: VisibilityGroup
    var priority: Int
    var minimumWidth: CGFloat
    var lastInteractionAt: Date
    var isVisible: Bool
}

struct LayoutSnapshot: Equatable {
    var screenWidth: CGFloat
    var notchWidth: CGFloat
    var reservedCenterWidth: CGFloat
    var sideBudget: CGFloat
    var spacing: CGFloat
    var fullscreenLike: Bool
    var effectiveCompactMode: Bool = false
    var effectiveSpacingMultiplier: CGFloat = 1

    static let zero = LayoutSnapshot(
        screenWidth: 0,
        notchWidth: 0,
        reservedCenterWidth: 0,
        sideBudget: 320,
        spacing: 8,
        fullscreenLike: false,
        effectiveCompactMode: false,
        effectiveSpacingMultiplier: 1
    )
}

struct MediaState: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var sourceApp: String

    static let unknown = MediaState(title: "Nothing Playing", artist: "", isPlaying: false, sourceApp: "")
}

struct SystemMetrics: Equatable {
    var batteryPercentage: Int
    var cpuUsage: Double
    var memoryUsage: Double

    static let zero = SystemMetrics(batteryPercentage: 0, cpuUsage: 0, memoryUsage: 0)
}

protocol MetricsProviding: AnyObject {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> { get }
    func start()
    func stop()
}

protocol MediaProviding: AnyObject {
    var mediaStatePublisher: AnyPublisher<MediaState, Never> { get }
    func start()
    func stop()
    func playPause()
    func nextTrack()
    func previousTrack()
}

enum ExternalResolvedState: Equatable {
    case hiddenApplied
    case mirrorOnly
    case downgraded(ExternalHideFailureReason)
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var icons: [MenuBarIcon]
    @Published private(set) var overflowIcons: [MenuBarIcon] = []
    @Published private(set) var layoutSnapshot: LayoutSnapshot = .zero
    @Published var spacing: CGFloat = 8
    @Published var notchDisplayMode: NotchDisplayMode = .respectNotch
    @Published var notchDefaultPolicy: NotchDefaultPolicy = .adaptiveAuto
    @Published var compactMenuBarSpacingEnabled: Bool = false

    @Published var isPanelEnabled: Bool = true
    @Published var isPanelExpanded: Bool = false
    @Published var showSystemStats: Bool = true
    @Published var useAccentTheme: Bool = false
    @Published var themeMode: ThemeMode = .system

    @Published var isNotchDropZoneEnabled: Bool = true
    @Published var instantExecutionEnabled: Bool = true
    @Published var workHubStyle: WorkHubStyle = .magneticDock
    @Published var interactiveMagnetEnabled: Bool = true
    @Published var isDropZoneHovered: Bool = false
    @Published private(set) var isDropTargetAreaActive: Bool = false
    @Published private(set) var notchDropState: NotchDropState = .idle
    @Published private(set) var dropVisualPhase: DropVisualPhase = .idle
    @Published private(set) var dragDynamics: DragDynamics = .zero
    @Published private(set) var magnetSnapStrength: CGFloat = 1
    @Published private(set) var droppedFiles: [DroppedFileDescriptor] = []
    @Published private(set) var availableDropActions: [NotchActionKind] = []
    @Published private(set) var notchActionMessage: String = ""
    @Published private(set) var notchActionIsError: Bool = false

    @Published var batteryPercentage: Int = 0
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var mediaState: MediaState = .unknown

    @Published private(set) var mirrorAuthState: MirrorAuthState = .unknown
    @Published private(set) var externalItems: [ExternalMenuBarItem] = []
    @Published private(set) var externalHiddenShelfItems: [ExternalMenuBarItem] = []
    @Published private(set) var externalVisibleItems: [ExternalMenuBarItem] = []
    @Published private(set) var externalOverflowItems: [ExternalMenuBarItem] = []
    @Published private(set) var externalPreferences: [String: ExternalIconPreference] = [:]
    @Published private(set) var externalLastOperationMessage: String = ""
    @Published private(set) var externalLastOperationIsWarning: Bool = false
    @Published private(set) var dragSession: DragSessionContext = .idle
    @Published private(set) var recommendedDropAction: NotchActionKind?
    @Published private(set) var targetedDropAction: NotchActionKind?
    @Published private(set) var lastReclaimedBytes: Int64 = 0

    private var dropResultResetWorkItem: DispatchWorkItem?
    private let dropResultVisibleDuration: TimeInterval = 0.82

    var visibleIcons: [MenuBarIcon] {
        icons.filter(\.isVisible)
    }

    var externalHiddenAppliedCount: Int {
        externalPreferences.values.reduce(into: 0) { count, pref in
            if pref.mode == .mirrorAndHide && pref.hiddenEnabled {
                count += 1
            }
        }
    }

    var externalDowngradedCount: Int {
        externalPreferences.values.reduce(into: 0) { count, pref in
            if pref.downgradeReason != nil {
                count += 1
            }
        }
    }

    var externalMirrorOnlyCount: Int {
        max(0, externalKnownCount - externalHiddenAppliedCount - externalDowngradedCount)
    }

    var externalHiddenShelfCount: Int {
        externalHiddenShelfItems.count
    }

    var externalHideCapableCount: Int {
        max(0, externalKnownCount - externalDowngradedCount)
    }

    var externalStatusSummary: String {
        "Visible \(externalVisibleItems.count) · HiddenShelf \(externalHiddenShelfCount) · Downgraded \(externalDowngradedCount)"
    }

    var externalHideStatsSummary: String {
        "Supported Hide \(externalHideCapableCount) · Applied \(externalHiddenAppliedCount) · Downgraded \(externalDowngradedCount)"
    }

    private var externalKnownCount: Int {
        let combined = externalItems.map(\.id) + externalHiddenShelfItems.map(\.id)
        return Set(combined).count
    }

    var canUndoLastDangerousAction: Bool {
        guard let lastUndoToken else { return false }
        return Date() <= lastUndoToken.expiresAt
    }

    private let defaultsKey = "menubar.icon.configuration.v2"
    private let externalDefaultsKey = "external.icon.preferences.v1"
    private let notchDisplayModeDefaultsKey = "menubar.notch.display.mode.v1"
    private let notchDefaultPolicyDefaultsKey = "menubar.notch.default.policy.v2"
    private let compactSpacingDefaultsKey = "menubar.compact.spacing.enabled.v1"
    private let workHubStyleDefaultsKey = "workhub.style.v2"
    private let interactiveMagnetDefaultsKey = "workhub.magnet.enabled.v2"
    private let defaults: UserDefaults
    private let metricsProvider: MetricsProviding
    private let mediaProvider: MediaProviding
    private let externalProvider: ExternalMenuBarProviding
    private let fileActionService: FileActionExecuting
    private var cancellables = Set<AnyCancellable>()
    private var dropContentKind: DropContentKind = .unsupported
    private var lastUndoToken: UndoToken?
    private var undoExpiryNonce = UUID()
    private var rawLayoutSnapshot: LayoutSnapshot = .zero
    private let preheatDuration: TimeInterval = 0.08
    private let dropCommitDuration: TimeInterval = 0.06

    init(
        metricsProvider: MetricsProviding = SystemMetricsService(),
        mediaProvider: MediaProviding = MediaService(),
        externalProvider: ExternalMenuBarProviding = ExternalMenuBarService(),
        fileActionService: FileActionExecuting = FileActionService(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.metricsProvider = metricsProvider
        self.mediaProvider = mediaProvider
        self.externalProvider = externalProvider
        self.fileActionService = fileActionService

        self.icons = [
            MenuBarIcon(id: "wifi", title: "Wi-Fi", shortTitle: "WiFi", group: .alwaysVisible, priority: 100, minimumWidth: 46, lastInteractionAt: .now, isVisible: true),
            MenuBarIcon(id: "battery", title: "Battery", shortTitle: "Bat", group: .alwaysVisible, priority: 90, minimumWidth: 42, lastInteractionAt: .now, isVisible: true),
            MenuBarIcon(id: "music", title: "Music", shortTitle: "Music", group: .smartHide, priority: 80, minimumWidth: 52, lastInteractionAt: .now, isVisible: true),
            MenuBarIcon(id: "clock", title: "Clock", shortTitle: "Clock", group: .alwaysVisible, priority: 70, minimumWidth: 48, lastInteractionAt: .now, isVisible: true),
            MenuBarIcon(id: "vpn", title: "VPN", shortTitle: "VPN", group: .hidden, priority: 10, minimumWidth: 36, lastInteractionAt: .now, isVisible: false)
        ]

        loadLayoutPreferences()
        loadIconConfiguration()
        loadExternalPreferences()
        bindServices()
        bindExternalService()

        metricsProvider.start()
        mediaProvider.start()

        mirrorAuthState = externalProvider.currentAuthState()
        if mirrorAuthState == .granted {
            externalProvider.start()
            externalProvider.refresh()
        }

        recalculateLayout(snapshot: layoutSnapshot)
        refreshDropCapabilities()
    }

    func recalculateLayout(snapshot: LayoutSnapshot) {
        rawLayoutSnapshot = snapshot
        let resolvedSnapshot = resolvedLayoutSnapshot(from: snapshot)
        layoutSnapshot = resolvedSnapshot
        spacing = resolvedSnapshot.spacing

        let always = sortedIcons(in: .alwaysVisible)
        let smart = sortedIcons(in: .smartHide)

        var usedWidth: CGFloat = 0
        var visibleIDs = Set<String>()

        for icon in always {
            visibleIDs.insert(icon.id)
            usedWidth += icon.minimumWidth + spacing
        }

        for icon in smart {
            let nextWidth = usedWidth + icon.minimumWidth + spacing
            if nextWidth <= resolvedSnapshot.sideBudget {
                visibleIDs.insert(icon.id)
                usedWidth = nextWidth
            }
        }

        icons = icons.map { icon in
            var copy = icon
            if icon.group == .hidden {
                copy.isVisible = false
            } else {
                copy.isVisible = visibleIDs.contains(icon.id)
            }
            return copy
        }

        overflowIcons = sortedIcons(in: .smartHide).filter { !visibleIDs.contains($0.id) }
        recalculateExternalLayout()
        persistIconConfiguration()
    }

    func setIconGroup(id: String, group: VisibilityGroup) {
        guard let index = icons.firstIndex(where: { $0.id == id }) else { return }
        icons[index].group = group
        recalculateLayout(snapshot: layoutSnapshot)
    }

    func registerInteraction(iconID: String) {
        guard let index = icons.firstIndex(where: { $0.id == iconID }) else { return }
        icons[index].lastInteractionAt = .now
        recalculateLayout(snapshot: layoutSnapshot)
    }

    func setTheme(mode: ThemeMode, accentEnabled: Bool) {
        themeMode = mode
        useAccentTheme = accentEnabled
    }

    func setNotchDisplayMode(_ mode: NotchDisplayMode) {
        guard notchDisplayMode != mode else { return }
        notchDisplayMode = mode
        persistLayoutPreferences()
        recalculateLayout(snapshot: rawLayoutSnapshot)
    }

    func applyDisplayPolicy(for screen: NSScreen, hasNotch: Bool) {
        _ = screen
        let resolvedMode: NotchDisplayMode
        switch notchDefaultPolicy {
        case .adaptiveAuto:
            resolvedMode = hasNotch ? .hideNotchLike : .respectNotch
        case .alwaysCompact:
            resolvedMode = .hideNotchLike
        case .alwaysRespect:
            resolvedMode = .respectNotch
        }

        guard notchDisplayMode != resolvedMode else { return }
        notchDisplayMode = resolvedMode
        persistLayoutPreferences()
    }

    func setNotchDefaultPolicy(_ policy: NotchDefaultPolicy) {
        guard notchDefaultPolicy != policy else { return }
        notchDefaultPolicy = policy
        persistLayoutPreferences()
        if let screen = NSScreen.main {
            let hasNotch = max(0, screen.frame.width - (screen.safeAreaInsets.left + screen.safeAreaInsets.right)) > 0
            applyDisplayPolicy(for: screen, hasNotch: hasNotch)
        }
        recalculateLayout(snapshot: rawLayoutSnapshot)
    }

    func setCompactMenuBarSpacingEnabled(_ enabled: Bool) {
        guard compactMenuBarSpacingEnabled != enabled else { return }
        compactMenuBarSpacingEnabled = enabled
        persistLayoutPreferences()
        recalculateLayout(snapshot: rawLayoutSnapshot)
    }

    func setWorkHubStyle(_ style: WorkHubStyle) {
        guard workHubStyle != style else { return }
        workHubStyle = style
        persistLayoutPreferences()
    }

    func setInteractiveMagnetEnabled(_ enabled: Bool) {
        guard interactiveMagnetEnabled != enabled else { return }
        interactiveMagnetEnabled = enabled
        if !enabled {
            magnetSnapStrength = 1
        }
        persistLayoutPreferences()
    }

    func setPanelExpanded(_ expanded: Bool) {
        isPanelExpanded = expanded
    }

    func setDropZoneHover(_ hovering: Bool) {
        if hovering {
            cancelDropResultAutoHide()
        }

        guard isDropZoneHovered != hovering else { return }
        isDropZoneHovered = hovering
        if hovering {
            if dragSession.isFileDrag {
                if let targetedDropAction {
                    notchDropState = .magnetFocus(targetedDropAction)
                    dropVisualPhase = .lock(targetedDropAction)
                } else if notchDropState == .preheat {
                    // Keep preheat briefly to avoid abrupt expansion on fast drags.
                } else {
                    notchDropState = .predrag
                    dropVisualPhase = .tracking
                }
            } else if notchDropState == .idle {
                notchDropState = .hovering
                dropVisualPhase = .hoverReveal
            }
            return
        }

        if !dragSession.isFileDrag, !canUndoLastDangerousAction {
            notchDropState = .idle
            notchActionMessage = ""
            notchActionIsError = false
            dropVisualPhase = .idle
            cancelDropResultAutoHide()
        }
    }

    func beginDragSession(with urls: [URL], shouldReveal: Bool = true) {
        cancelDropResultAutoHide()
        dragSession = DragSessionContext(
            isFileDrag: true,
            hoveredAction: nil,
            enteredAt: .now
        )
        dragDynamics = .zero
        magnetSnapStrength = 1

        let classification = fileActionService.classify(urls: urls)
        droppedFiles = classification.descriptors
        dropContentKind = classification.kind
        recommendedDropAction = classification.recommendedAction
        targetedDropAction = nil
        refreshDropCapabilities()
        if shouldReveal {
            notchDropState = .preheat
            dropVisualPhase = .dragReveal
        } else {
            notchDropState = .idle
            dropVisualPhase = .idle
            isDropZoneHovered = false
        }

        let capturedEnteredAt = dragSession.enteredAt
        DispatchQueue.main.asyncAfter(deadline: .now() + preheatDuration) { [weak self] in
            guard let self else { return }
            guard self.dragSession.isFileDrag else { return }
            guard self.dragSession.enteredAt == capturedEnteredAt else { return }
            guard self.targetedDropAction == nil else { return }
            if !self.isDropTargetAreaActive {
                return
            }
            if case .preheat = self.notchDropState {
                self.notchDropState = .predrag
                self.dropVisualPhase = .tracking
            }
        }
    }

    func setDropTargetAreaActive(_ active: Bool) {
        guard isDropTargetAreaActive != active else { return }
        isDropTargetAreaActive = active
        setDropZoneHover(active)
    }

    func updateDragTarget(_ action: NotchActionKind?) {
        guard dragSession.isFileDrag else { return }
        guard targetedDropAction != action || dragSession.hoveredAction != action else { return }

        targetedDropAction = action
        if dragSession.hoveredAction != action {
            dragSession.hoveredAction = action
        }

        if let action {
            let nextDropState = NotchDropState.magnetFocus(action)
            let nextVisualPhase = DropVisualPhase.lock(action)
            if notchDropState != nextDropState {
                notchDropState = nextDropState
            }
            if dropVisualPhase != nextVisualPhase {
                dropVisualPhase = nextVisualPhase
            }
        } else {
            if notchDropState != .predrag {
                notchDropState = .predrag
            }
            if dropVisualPhase != .tracking {
                dropVisualPhase = .tracking
            }
        }
    }

    func updateDragDynamics(_ dynamics: DragDynamics) {
        guard dragSession.isFileDrag else { return }
        let current = dragDynamics
        let deltaX = dynamics.lastPoint.x - current.lastPoint.x
        let deltaY = dynamics.lastPoint.y - current.lastPoint.y
        let pointDelta = sqrt((deltaX * deltaX) + (deltaY * deltaY))
        let speedDelta = abs(dynamics.speed - current.speed)

        // Skip near-identical updates to reduce render churn during slow drags.
        guard pointDelta > 1.5 || speedDelta > 40 else { return }

        dragDynamics = dynamics

        guard interactiveMagnetEnabled else {
            if magnetSnapStrength != 1 {
                magnetSnapStrength = 1
            }
            return
        }

        let speed = min(max(dynamics.speed, 0), 2200)
        let normalized = min(1, speed / 1300)
        let nextStrength = max(0.38, 1 - (normalized * 0.55))
        if abs(nextStrength - magnetSnapStrength) > 0.015 {
            magnetSnapStrength = nextStrength
        }
    }

    func endDragSession() {
        dragSession = .idle
        targetedDropAction = nil
        recommendedDropAction = nil
        dragDynamics = .zero
        magnetSnapStrength = 1
        switch notchDropState {
        case .preheat, .predrag, .magnetFocus(_), .hovering:
            if !isDropZoneHovered, !canUndoLastDangerousAction {
                notchDropState = .idle
                notchActionMessage = ""
                notchActionIsError = false
                dropVisualPhase = .idle
                cancelDropResultAutoHide()
            } else if isDropZoneHovered {
                notchDropState = .hovering
                dropVisualPhase = .hoverReveal
                cancelDropResultAutoHide()
            } else {
                scheduleDropStateAutoHide()
            }
        default:
            if !isDropZoneHovered, !canUndoLastDangerousAction {
                dropVisualPhase = .idle
                scheduleDropStateAutoHide()
            } else if isDropZoneHovered {
                dropVisualPhase = .hoverReveal
                cancelDropResultAutoHide()
            }
            break
        }
    }

    func handleDroppedItems(_ urls: [URL], preferredAction: NotchActionKind? = nil) {
        guard isNotchDropZoneEnabled else { return }

        let classification = fileActionService.classify(urls: urls)
        droppedFiles = classification.descriptors
        dropContentKind = classification.kind
        recommendedDropAction = classification.recommendedAction
        refreshDropCapabilities()

        guard !droppedFiles.isEmpty else {
            notchDropState = .failure
            dropVisualPhase = .result
            setNotchActionMessage("No valid files were dropped.", error: true)
            scheduleDropStateAutoHide()
            endDragSession()
            return
        }

        notchDropState = .hovering
        dropVisualPhase = .tracking

        let selectedAction = preferredAction ?? targetedDropAction ?? classification.recommendedAction
        if instantExecutionEnabled,
           let selectedAction,
           availableDropActions.contains(selectedAction) {
            let committedFiles = droppedFiles
            notchDropState = .dropCommit(selectedAction)
            dropVisualPhase = .commit(selectedAction)
            DispatchQueue.main.asyncAfter(deadline: .now() + dropCommitDuration) { [weak self] in
                guard let self else { return }
                self.performNotchAction(selectedAction, files: committedFiles)
                self.endDragSession()
            }
        } else {
            setNotchActionMessage("Choose an action to process \(droppedFiles.count) file(s).", error: false)
            scheduleDropStateAutoHide()
            endDragSession()
        }
    }

    func performNotchAction(_ action: NotchActionKind, files: [DroppedFileDescriptor]) {
        let inputs = files.isEmpty ? droppedFiles : files
        guard !inputs.isEmpty else {
            notchDropState = .failure
            dropVisualPhase = .result
            setNotchActionMessage("Drop files first.", error: true)
            scheduleDropStateAutoHide()
            return
        }

        guard availableDropActions.contains(action) else {
            notchDropState = .failure
            dropVisualPhase = .result
            setNotchActionMessage("Action unavailable for current file type.", error: true)
            scheduleDropStateAutoHide()
            return
        }

        notchDropState = .processing
        dropVisualPhase = .processing

        do {
            let result = try fileActionService.execute(action: action, inputs: inputs, outputPolicy: .sourceDirectory)
            notchDropState = .success
            dropVisualPhase = .result
            setNotchActionMessage(result.message, error: false)
            lastReclaimedBytes = result.spaceDeltaBytes

            lastUndoToken = result.undoToken
            if let undoToken = result.undoToken {
                armUndoExpiry(for: undoToken)
            }
        } catch {
            notchDropState = .failure
            dropVisualPhase = .result
            setNotchActionMessage(error.localizedDescription, error: true)
            scheduleDropStateAutoHide()
        }

        scheduleDropStateAutoHide()
        endDragSession()
    }

    func undoLastDangerousAction() {
        guard let token = lastUndoToken else {
            setNotchActionMessage("No undo history available.", error: true)
            notchDropState = .failure
            dropVisualPhase = .result
            return
        }

        guard canUndoLastDangerousAction else {
            setNotchActionMessage("Undo window expired.", error: true)
            notchDropState = .failure
            dropVisualPhase = .result
            lastUndoToken = nil
            return
        }

        if fileActionService.undo(token: token) {
            notchDropState = .success
            dropVisualPhase = .result
            setNotchActionMessage("Undo completed.", error: false)
            lastUndoToken = nil
        } else {
            notchDropState = .failure
            dropVisualPhase = .result
            setNotchActionMessage("Undo failed. Restore manually if needed.", error: true)
        }

        scheduleDropStateAutoHide()
    }

    func refreshDropCapabilities() {
        availableDropActions = fileActionService.availableActions(for: dropContentKind)
    }

    func openWorkbenchFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileActionService.workbenchFolderURL()])
    }

    func playPause() {
        mediaProvider.playPause()
    }

    func nextTrack() {
        mediaProvider.nextTrack()
    }

    func previousTrack() {
        mediaProvider.previousTrack()
    }

    func requestAXPermission() {
        mirrorAuthState = externalProvider.requestPermission()
        if mirrorAuthState == .granted {
            setExternalStatusMessage("Accessibility granted. External icons enabled.", warning: false)
        } else {
            setExternalStatusMessage("Accessibility denied. External icons remain mirror-disabled.", warning: true)
        }
        refreshExternalItems()
    }

    func openAXSettings() {
        externalProvider.openSystemSettings()
    }

    func setExternalItemMode(itemID: String, mode: ExternalItemVisibilityMode) {
        var preference = preference(for: itemID)
        let result = externalProvider.setVisibilityMode(mode, for: itemID)

        preference.mode = result.effectiveMode
        preference.hiddenEnabled = result.effectiveMode == .mirrorAndHide
        preference.downgradeReason = result.downgradeReason

        externalPreferences[itemID] = preference
        persistExternalPreferences()
        recalculateExternalLayout()

        let displayName = externalItems.first(where: { $0.id == itemID })?.displayName
            ?? externalHiddenShelfItems.first(where: { $0.id == itemID })?.displayName
            ?? itemID
        if let reason = result.downgradeReason {
            setExternalStatusMessage("Hide unsupported for \(displayName): \(reason.rawValue). Fallback to Mirror only.", warning: true)
        } else if result.effectiveMode == .mirrorAndHide {
            setExternalStatusMessage("Hide applied for \(displayName).", warning: false)
        } else {
            setExternalStatusMessage("Mirror only mode set for \(displayName).", warning: false)
        }
    }

    func toggleExternalItemHidden(itemID: String, isHidden: Bool) {
        setExternalItemMode(itemID: itemID, mode: isHidden ? .mirrorAndHide : .mirrorOnly)
    }

    func setExternalItemPinned(itemID: String, pinned: Bool) {
        var preference = preference(for: itemID)
        preference.userPinned = pinned
        externalPreferences[itemID] = preference
        persistExternalPreferences()
        recalculateExternalLayout()
    }

    func refreshExternalItems() {
        mirrorAuthState = externalProvider.currentAuthState()
        guard mirrorAuthState == .granted else {
            externalItems = []
            externalHiddenShelfItems = []
            externalVisibleItems = []
            externalOverflowItems = []
            setExternalStatusMessage("Accessibility required. Grant permission to mirror or hide icons.", warning: true)
            return
        }
        externalProvider.refresh()
    }

    func performExternalItemPrimaryAction(itemID: String) {
        let displayName = externalItems.first(where: { $0.id == itemID })?.displayName
            ?? externalHiddenShelfItems.first(where: { $0.id == itemID })?.displayName
            ?? itemID
        guard externalProvider.performPrimaryAction(for: itemID) else {
            setExternalStatusMessage("Could not trigger \(displayName). Open it from original menu bar.", warning: true)
            return
        }
        setExternalStatusMessage("Opened \(displayName).", warning: false)
        if let index = externalItems.firstIndex(where: { $0.id == itemID }) {
            externalItems[index].lastInteractionAt = .now
            recalculateExternalLayout()
        }
    }

    func externalMode(for itemID: String) -> ExternalItemVisibilityMode {
        preference(for: itemID).mode
    }

    func isExternalPinned(itemID: String) -> Bool {
        preference(for: itemID).userPinned
    }

    func externalDowngradeReason(for itemID: String) -> ExternalHideFailureReason? {
        preference(for: itemID).downgradeReason
    }

    func resolvedExternalState(for itemID: String) -> ExternalResolvedState {
        let pref = preference(for: itemID)
        if let reason = pref.downgradeReason {
            return .downgraded(reason)
        }
        if pref.mode == .mirrorAndHide && pref.hiddenEnabled {
            return .hiddenApplied
        }
        return .mirrorOnly
    }

    func clearExternalStatusMessage() {
        externalLastOperationMessage = ""
        externalLastOperationIsWarning = false
    }

    func shutdown() {
        metricsProvider.stop()
        mediaProvider.stop()
        externalProvider.stop()
    }

    private func sortedIcons(in group: VisibilityGroup) -> [MenuBarIcon] {
        icons
            .filter { $0.group == group }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.lastInteractionAt > $1.lastInteractionAt
                }
                return $0.priority > $1.priority
            }
    }

    private func bindServices() {
        metricsProvider.metricsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.batteryPercentage = metrics.batteryPercentage
                self?.cpuUsage = metrics.cpuUsage
                self?.memoryUsage = metrics.memoryUsage
            }
            .store(in: &cancellables)

        mediaProvider.mediaStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.mediaState = state
            }
            .store(in: &cancellables)
    }

    private func bindExternalService() {
        externalProvider.externalItemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.updateExternalItems(items)
            }
            .store(in: &cancellables)

        externalProvider.hiddenShelfPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.externalHiddenShelfItems = items
            }
            .store(in: &cancellables)
    }

    private func updateExternalItems(_ items: [ExternalMenuBarItem]) {
        let previousByID = Dictionary(uniqueKeysWithValues: externalItems.map { ($0.id, $0) })
        externalItems = items.map { item in
            guard let previous = previousByID[item.id] else {
                return item
            }

            var merged = item
            if previous.lastInteractionAt > merged.lastInteractionAt {
                merged.lastInteractionAt = previous.lastInteractionAt
            }
            return merged
        }

        recalculateExternalLayout()
    }

    private func recalculateExternalLayout() {
        guard mirrorAuthState == .granted else {
            externalVisibleItems = []
            externalOverflowItems = []
            return
        }

        let sorted = externalItems.sorted { lhs, rhs in
            let leftPinned = preference(for: lhs.id).userPinned
            let rightPinned = preference(for: rhs.id).userPinned
            if leftPinned != rightPinned {
                return leftPinned && !rightPinned
            }
            if lhs.frameInScreen.minX != rhs.frameInScreen.minX {
                return lhs.frameInScreen.minX > rhs.frameInScreen.minX
            }
            return lhs.lastInteractionAt > rhs.lastInteractionAt
        }

        let mirrorBudget = max(160, layoutSnapshot.sideBudget - 20)
        var used: CGFloat = 0
        var visibleIDs = Set<String>()

        for item in sorted where item.isVisibleInSystemBar {
            let required = item.estimatedWidth + spacing
            if used + required <= mirrorBudget {
                visibleIDs.insert(item.id)
                used += required
            }
        }

        externalVisibleItems = sorted.filter { visibleIDs.contains($0.id) }
        externalOverflowItems = sorted.filter { !visibleIDs.contains($0.id) }
    }

    private func preference(for itemID: String) -> ExternalIconPreference {
        externalPreferences[itemID] ?? .default
    }

    private func loadIconConfiguration() {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([MenuBarIcon].self, from: data)
        else {
            return
        }

        let decodedMap = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        icons = icons.map { icon in
            guard let saved = decodedMap[icon.id] else { return icon }
            return MenuBarIcon(
                id: icon.id,
                title: icon.title,
                shortTitle: icon.shortTitle,
                group: saved.group,
                priority: saved.priority,
                minimumWidth: icon.minimumWidth,
                lastInteractionAt: saved.lastInteractionAt,
                isVisible: saved.isVisible
            )
        }
    }

    private func persistIconConfiguration() {
        guard let data = try? JSONEncoder().encode(icons) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func loadExternalPreferences() {
        guard
            let data = defaults.data(forKey: externalDefaultsKey),
            let decoded = try? JSONDecoder().decode([String: ExternalIconPreference].self, from: data)
        else {
            return
        }
        externalPreferences = decoded
    }

    private func loadLayoutPreferences() {
        if let raw = defaults.string(forKey: notchDefaultPolicyDefaultsKey),
           let policy = NotchDefaultPolicy(rawValue: raw) {
            notchDefaultPolicy = policy
        }
        if let raw = defaults.string(forKey: notchDisplayModeDefaultsKey),
           let mode = NotchDisplayMode(rawValue: raw) {
            notchDisplayMode = mode
        }
        if let raw = defaults.string(forKey: workHubStyleDefaultsKey),
           let style = WorkHubStyle(rawValue: raw) {
            workHubStyle = style
        }
        compactMenuBarSpacingEnabled = defaults.bool(forKey: compactSpacingDefaultsKey)
        if defaults.object(forKey: interactiveMagnetDefaultsKey) != nil {
            interactiveMagnetEnabled = defaults.bool(forKey: interactiveMagnetDefaultsKey)
        }
    }

    private func persistLayoutPreferences() {
        defaults.set(notchDefaultPolicy.rawValue, forKey: notchDefaultPolicyDefaultsKey)
        defaults.set(notchDisplayMode.rawValue, forKey: notchDisplayModeDefaultsKey)
        defaults.set(compactMenuBarSpacingEnabled, forKey: compactSpacingDefaultsKey)
        defaults.set(workHubStyle.rawValue, forKey: workHubStyleDefaultsKey)
        defaults.set(interactiveMagnetEnabled, forKey: interactiveMagnetDefaultsKey)
    }

    private func resolvedLayoutSnapshot(from snapshot: LayoutSnapshot) -> LayoutSnapshot {
        var resolved = snapshot
        let compactMode = notchDisplayMode == .hideNotchLike

        let compactSpacingFromSideBudget = compactSpacing(sideBudget: snapshot.sideBudget, fullscreenLike: snapshot.fullscreenLike)
        let respectSpacingFromSideBudget = respectSpacing(sideBudget: snapshot.sideBudget, fullscreenLike: snapshot.fullscreenLike)

        if compactMode {
            let compactReservedCenterWidth: CGFloat = 48
            resolved.notchWidth = 0
            resolved.reservedCenterWidth = compactReservedCenterWidth
            resolved.sideBudget = max(220, (snapshot.screenWidth - compactReservedCenterWidth) / 2)
            resolved.spacing = compactSpacing(sideBudget: resolved.sideBudget, fullscreenLike: snapshot.fullscreenLike)
            resolved.effectiveSpacingMultiplier = compactSpacingFromSideBudget / max(respectSpacingFromSideBudget, 0.001)
        } else {
            resolved.spacing = respectSpacing(sideBudget: resolved.sideBudget, fullscreenLike: snapshot.fullscreenLike)
            resolved.effectiveSpacingMultiplier = 1
        }

        if compactMenuBarSpacingEnabled {
            resolved.spacing = max(3.5, resolved.spacing * 0.90)
            resolved.effectiveSpacingMultiplier *= 0.90
        }

        resolved.effectiveCompactMode = compactMode
        return resolved
    }

    private func persistExternalPreferences() {
        guard let data = try? JSONEncoder().encode(externalPreferences) else { return }
        defaults.set(data, forKey: externalDefaultsKey)
    }

    private func setExternalStatusMessage(_ message: String, warning: Bool) {
        externalLastOperationMessage = message
        externalLastOperationIsWarning = warning
    }

    private func setNotchActionMessage(_ message: String, error: Bool) {
        notchActionMessage = message
        notchActionIsError = error
        if message.isEmpty {
            cancelDropResultAutoHide()
        }
    }

    private func scheduleDropStateAutoHide() {
        cancelDropResultAutoHide()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isDropZoneHovered || self.dragSession.isFileDrag {
                return
            }
            if self.canUndoLastDangerousAction {
                return
            }

            self.notchDropState = .idle
            self.dropVisualPhase = .idle
            self.notchActionMessage = ""
            self.notchActionIsError = false
            self.targetedDropAction = nil
        }
        dropResultResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dropResultVisibleDuration, execute: workItem)
    }

    private func cancelDropResultAutoHide() {
        dropResultResetWorkItem?.cancel()
        dropResultResetWorkItem = nil
    }

    private func armUndoExpiry(for token: UndoToken) {
        let nonce = UUID()
        undoExpiryNonce = nonce
        let delay = max(0, token.expiresAt.timeIntervalSinceNow)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.undoExpiryNonce == nonce else { return }
            if !self.canUndoLastDangerousAction {
                self.lastUndoToken = nil
            }
        }
    }

    private func respectSpacing(sideBudget: CGFloat, fullscreenLike: Bool) -> CGFloat {
        let base = baseSpacing(sideBudget: sideBudget)
        if fullscreenLike {
            return max(4, base * 0.72)
        }
        return base
    }

    private func compactSpacing(sideBudget: CGFloat, fullscreenLike: Bool) -> CGFloat {
        let base = baseSpacing(sideBudget: sideBudget)
        var compact = clamp(base * 0.72, lower: 3.5, upper: 9.5)
        if fullscreenLike {
            compact = max(3.5, compact * 0.9)
        }
        return compact
    }

    private func baseSpacing(sideBudget: CGFloat) -> CGFloat {
        clamp(sideBudget / 180, lower: 6, upper: 14)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}
