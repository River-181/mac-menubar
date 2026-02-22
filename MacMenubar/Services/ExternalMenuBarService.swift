import ApplicationServices
import Combine
import Foundation

@MainActor
final class ExternalMenuBarService: ExternalMenuBarProviding {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    var hiddenShelfPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        hiddenShelfSubject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let hiddenShelfSubject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let permissionManager: AXPermissionProviding
    private let scanner: AXMenuBarScanner
    private let actionBridge: AXActionBridging
    private let staleTTL: TimeInterval
    private let hiddenShelfStaleThreshold: TimeInterval
    private let pollingInterval: TimeInterval
    private let pollingTolerance: TimeInterval
    private let iconCaptureIntervalTicks: Int

    private var timer: Timer?
    private var cachedItems: [String: ExternalMenuBarItem] = [:]
    private var lastKnownItems: [String: ExternalMenuBarItem] = [:]
    private var elementByID: [String: AXUIElement] = [:]
    private var modeByID: [String: ExternalItemVisibilityMode] = [:]
    private var hiddenSinceByID: [String: Date] = [:]
    private var pollTick: Int = 0
    private var forceIconCaptureOnNextRefresh: Bool = true

    init(
        permissionManager: AXPermissionProviding = AXPermissionManager(),
        scanner: AXMenuBarScanner = AXMenuBarScanner(),
        actionBridge: AXActionBridging = AXActionBridge(),
        staleTTL: TimeInterval = 3,
        hiddenShelfStaleThreshold: TimeInterval = 12,
        pollingInterval: TimeInterval = 1.5,
        pollingTolerance: TimeInterval = 0.5,
        iconCaptureIntervalTicks: Int = 8
    ) {
        self.permissionManager = permissionManager
        self.scanner = scanner
        self.actionBridge = actionBridge
        self.staleTTL = staleTTL
        self.hiddenShelfStaleThreshold = hiddenShelfStaleThreshold
        self.pollingInterval = pollingInterval
        self.pollingTolerance = pollingTolerance
        self.iconCaptureIntervalTicks = max(2, iconCaptureIntervalTicks)
    }

    func start() {
        guard currentAuthState() == .granted else {
            subject.send([])
            hiddenShelfSubject.send([])
            stop()
            return
        }
        guard timer == nil else {
            refresh()
            return
        }

        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollRefresh()
            }
        }
        timer.tolerance = pollingTolerance
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        pollTick += 1
        performRefresh(allowIconCapture: shouldCaptureIconsThisRefresh())
    }

    private func pollRefresh() {
        pollTick += 1
        performRefresh(allowIconCapture: shouldCaptureIconsThisRefresh())
    }

    private func performRefresh(allowIconCapture: Bool) {
        guard currentAuthState() == .granted else {
            cachedItems.removeAll()
            lastKnownItems.removeAll()
            elementByID.removeAll()
            modeByID.removeAll()
            hiddenSinceByID.removeAll()
            pollTick = 0
            subject.send([])
            hiddenShelfSubject.send([])
            return
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let scanned = scanner.scan(excludingBundleID: ownBundleID, captureIcons: allowIconCapture)
        let now = Date()
        let scannedIDs = Set(scanned.map { $0.item.id })

        for entry in scanned {
            let previouslyKnown = cachedItems[entry.item.id] != nil
            var item = entry.item
            item.isVisibleInSystemBar = true
            item.shelfState = .none
            if let previousItem = lastKnownItems[item.id], item.iconPNGData == nil {
                item.iconPNGData = previousItem.iconPNGData
            }

            cachedItems[item.id] = item
            lastKnownItems[item.id] = item
            elementByID[item.id] = entry.element

            // Re-apply hide only when item re-appears after previously disappearing.
            if modeByID[item.id] == .mirrorAndHide && !previouslyKnown {
                _ = actionBridge.setHidden(true, for: entry.element)
            }
        }

        let staleIDs = cachedItems.compactMap { pair in
            now.timeIntervalSince(pair.value.lastSeenAt) > staleTTL ? pair.key : nil
        }

        for staleID in staleIDs {
            cachedItems.removeValue(forKey: staleID)
            elementByID.removeValue(forKey: staleID)
        }

        let sortedVisible = cachedItems.values.sorted { lhs, rhs in
            lhs.frameInScreen.minX > rhs.frameInScreen.minX
        }
        if shouldPublishChanges(from: subject.value, to: sortedVisible) {
            subject.send(sortedVisible)
        }
        publishHiddenShelf(scannedIDs: scannedIDs, now: now)
    }

    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult {
        guard currentAuthState() == .granted else {
            return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: .permissionDenied)
        }

        switch mode {
        case .mirrorOnly:
            if let element = elementByID[itemID] {
                _ = actionBridge.setHidden(false, for: element)
            }
            modeByID[itemID] = .mirrorOnly
            hiddenSinceByID.removeValue(forKey: itemID)
            publishHiddenShelf(scannedIDs: Set(cachedItems.keys), now: .now)
            return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: nil)

        case .mirrorAndHide:
            guard let element = elementByID[itemID] else {
                return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: .actionFailed)
            }

            if let reason = actionBridge.setHidden(true, for: element) {
                modeByID[itemID] = .mirrorOnly
                return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: reason)
            }

            modeByID[itemID] = .mirrorAndHide
            hiddenSinceByID[itemID] = .now
            forceIconCaptureOnNextRefresh = true
            publishHiddenShelf(scannedIDs: Set(cachedItems.keys), now: .now)
            return ExternalModeUpdateResult(effectiveMode: .mirrorAndHide, downgradeReason: nil)
        }
    }

    func revealHiddenItem(_ itemID: String) -> Bool {
        guard modeByID[itemID] == .mirrorAndHide else {
            return false
        }
        guard let element = elementByID[itemID] else {
            return false
        }

        if actionBridge.setHidden(false, for: element) == nil {
            modeByID[itemID] = .mirrorOnly
            hiddenSinceByID.removeValue(forKey: itemID)
            refresh()
            return true
        }
        return false
    }

    func performPrimaryAction(for itemID: String) -> Bool {
        guard currentAuthState() == .granted else {
            return false
        }

        if let element = elementByID[itemID] {
            let frame = cachedItems[itemID]?.frameInScreen ?? lastKnownItems[itemID]?.frameInScreen
            return actionBridge.performPrimaryAction(on: element, fallbackFrame: frame)
        }

        if let frame = lastKnownItems[itemID]?.frameInScreen {
            return actionBridge.performFallbackClick(frame: frame)
        }

        return false
    }

    func currentAuthState() -> MirrorAuthState {
        permissionManager.currentState()
    }

    func requestPermission() -> MirrorAuthState {
        let state = permissionManager.requestPermission()
        if state == .granted {
            forceIconCaptureOnNextRefresh = true
            start()
        } else {
            stop()
            subject.send([])
            hiddenShelfSubject.send([])
        }
        return state
    }

    func openSystemSettings() {
        permissionManager.openAccessibilitySettings()
    }

    private func publishHiddenShelf(scannedIDs: Set<String>, now: Date) {
        var shelf: [ExternalMenuBarItem] = []

        for (itemID, mode) in modeByID where mode == .mirrorAndHide {
            if scannedIDs.contains(itemID) {
                hiddenSinceByID.removeValue(forKey: itemID)
                continue
            }

            guard var item = lastKnownItems[itemID] else { continue }

            let hiddenSince = hiddenSinceByID[itemID] ?? now
            hiddenSinceByID[itemID] = hiddenSince

            item.isVisibleInSystemBar = false
            item.shelfState = now.timeIntervalSince(hiddenSince) > hiddenShelfStaleThreshold ? .staleHidden : .hidden
            item.lastSeenAt = now
            shelf.append(item)
        }

        let sorted = shelf.sorted { lhs, rhs in
            lhs.frameInScreen.minX > rhs.frameInScreen.minX
        }
        if shouldPublishChanges(from: hiddenShelfSubject.value, to: sorted) {
            hiddenShelfSubject.send(sorted)
        }
    }

    private func shouldCaptureIconsThisRefresh() -> Bool {
        if forceIconCaptureOnNextRefresh {
            forceIconCaptureOnNextRefresh = false
            return true
        }
        return pollTick % iconCaptureIntervalTicks == 0
    }

    private func shouldPublishChanges(from current: [ExternalMenuBarItem], to next: [ExternalMenuBarItem]) -> Bool {
        guard current.count == next.count else { return true }
        guard !current.isEmpty else { return false }

        for (lhs, rhs) in zip(current, next) {
            if lhs.id != rhs.id { return true }
            if lhs.ownerBundleID != rhs.ownerBundleID { return true }
            if lhs.displayName != rhs.displayName { return true }
            if lhs.frameInScreen != rhs.frameInScreen { return true }
            if lhs.isVisibleInSystemBar != rhs.isVisibleInSystemBar { return true }
            if lhs.supportsPressAction != rhs.supportsPressAction { return true }
            if lhs.shelfState != rhs.shelfState { return true }
            if lhs.iconPNGData != rhs.iconPNGData { return true }
        }

        // Ignore timestamp-only updates to reduce unnecessary UI refresh churn.
        return false
    }
}
