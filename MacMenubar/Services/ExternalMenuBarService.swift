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

    private var timer: Timer?
    private var cachedItems: [String: ExternalMenuBarItem] = [:]
    private var lastKnownItems: [String: ExternalMenuBarItem] = [:]
    private var elementByID: [String: AXUIElement] = [:]
    private var modeByID: [String: ExternalItemVisibilityMode] = [:]
    private var hiddenSinceByID: [String: Date] = [:]

    init(
        permissionManager: AXPermissionProviding = AXPermissionManager(),
        scanner: AXMenuBarScanner = AXMenuBarScanner(),
        actionBridge: AXActionBridging = AXActionBridge(),
        staleTTL: TimeInterval = 3,
        hiddenShelfStaleThreshold: TimeInterval = 12
    ) {
        self.permissionManager = permissionManager
        self.scanner = scanner
        self.actionBridge = actionBridge
        self.staleTTL = staleTTL
        self.hiddenShelfStaleThreshold = hiddenShelfStaleThreshold
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
        let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = 0.25
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard currentAuthState() == .granted else {
            cachedItems.removeAll()
            lastKnownItems.removeAll()
            elementByID.removeAll()
            modeByID.removeAll()
            hiddenSinceByID.removeAll()
            subject.send([])
            hiddenShelfSubject.send([])
            return
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let scanned = scanner.scan(excludingBundleID: ownBundleID)
        let now = Date()
        let scannedIDs = Set(scanned.map { $0.item.id })

        for entry in scanned {
            var item = entry.item
            item.isVisibleInSystemBar = true
            item.shelfState = .none

            cachedItems[item.id] = item
            lastKnownItems[item.id] = item
            elementByID[item.id] = entry.element

            // Re-apply hide mode to reduce temporary reappearance.
            if modeByID[item.id] == .mirrorAndHide {
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
        subject.send(sortedVisible)
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
        hiddenShelfSubject.send(sorted)
    }
}
