import ApplicationServices
import Combine
import Foundation

@MainActor
final class ExternalMenuBarService: ExternalMenuBarProviding {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let permissionManager: AXPermissionProviding
    private let scanner: AXMenuBarScanner
    private let actionBridge: AXActionBridging
    private let staleTTL: TimeInterval

    private var timer: Timer?
    private var cachedItems: [String: ExternalMenuBarItem] = [:]
    private var elementByID: [String: AXUIElement] = [:]
    private var modeByID: [String: ExternalItemVisibilityMode] = [:]

    init(
        permissionManager: AXPermissionProviding = AXPermissionManager(),
        scanner: AXMenuBarScanner = AXMenuBarScanner(),
        actionBridge: AXActionBridging = AXActionBridge(),
        staleTTL: TimeInterval = 3
    ) {
        self.permissionManager = permissionManager
        self.scanner = scanner
        self.actionBridge = actionBridge
        self.staleTTL = staleTTL
    }

    func start() {
        guard currentAuthState() == .granted else {
            subject.send([])
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
            elementByID.removeAll()
            subject.send([])
            return
        }

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let scanned = scanner.scan(excludingBundleID: ownBundleID)
        let now = Date()

        for entry in scanned {
            cachedItems[entry.item.id] = entry.item
            elementByID[entry.item.id] = entry.element
        }

        let staleIDs = cachedItems.compactMap { pair in
            now.timeIntervalSince(pair.value.lastSeenAt) > staleTTL ? pair.key : nil
        }
        for staleID in staleIDs {
            cachedItems.removeValue(forKey: staleID)
            elementByID.removeValue(forKey: staleID)
            modeByID.removeValue(forKey: staleID)
        }

        let sorted = cachedItems.values.sorted { lhs, rhs in
            lhs.frameInScreen.minX > rhs.frameInScreen.minX
        }
        subject.send(sorted)
    }

    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult {
        guard currentAuthState() == .granted else {
            return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: .permissionDenied)
        }

        guard let element = elementByID[itemID] else {
            return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: .actionFailed)
        }

        switch mode {
        case .mirrorOnly:
            _ = actionBridge.setHidden(false, for: element)
            modeByID[itemID] = .mirrorOnly
            return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: nil)
        case .mirrorAndHide:
            if let reason = actionBridge.setHidden(true, for: element) {
                modeByID[itemID] = .mirrorOnly
                return ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: reason)
            }
            modeByID[itemID] = .mirrorAndHide
            return ExternalModeUpdateResult(effectiveMode: .mirrorAndHide, downgradeReason: nil)
        }
    }

    func performPrimaryAction(for itemID: String) -> Bool {
        guard currentAuthState() == .granted else {
            return false
        }
        guard let element = elementByID[itemID] else {
            return false
        }
        let frame = cachedItems[itemID]?.frameInScreen
        return actionBridge.performPrimaryAction(on: element, fallbackFrame: frame)
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
        }
        return state
    }

    func openSystemSettings() {
        permissionManager.openAccessibilitySettings()
    }
}
