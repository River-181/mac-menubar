import AppKit
import Combine
import Foundation

private enum AXScanCadence {
    case idle
    case active

    var interval: TimeInterval {
        switch self {
        case .idle: return 2.4
        case .active: return 0.8
        }
    }

    var tolerance: TimeInterval {
        switch self {
        case .idle: return 0.7
        case .active: return 0.2
        }
    }
}

@MainActor
final class AXIconSourceService: IconSourceProviding, ExternalIconProviding {
    var itemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    var authState: MirrorAuthState {
        permissionManager.currentState()
    }

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let permissionManager: AXPermissionManager
    private let scanner: AXMenuBarScanner
    private var timer: Timer?
    private var cadence: AXScanCadence = .idle
    private var started = false
    private var lastSignature = ""
    private var cacheByID: [String: ExternalMenuBarItem] = [:]
    private var lastDetailedCaptureAt: Date = .distantPast

    init(permissionManager: AXPermissionManager = AXPermissionManager(), scanner: AXMenuBarScanner = AXMenuBarScanner()) {
        self.permissionManager = permissionManager
        self.scanner = scanner
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        started = true
        guard authState == .granted else {
            subject.send([])
            return
        }
        refresh()
        scheduleTimer()
    }

    func refresh() {
        guard authState == .granted else {
            cacheByID.removeAll()
            lastSignature = ""
            subject.send([])
            return
        }
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let now = Date()
        let shouldCaptureIcons = now.timeIntervalSince(lastDetailedCaptureAt) >= 8
        if shouldCaptureIcons {
            lastDetailedCaptureAt = now
        }

        let scanned = scanner.scan(excludingBundleID: ownBundle, captureIcons: shouldCaptureIcons)
        var merged = scanned.map(\.item)
        if !shouldCaptureIcons {
            merged = merged.map { item in
                var resolved = item
                if resolved.imageData == nil {
                    resolved.imageData = cacheByID[item.id]?.imageData
                }
                return resolved
            }
        }

        let signature = makeSignature(for: merged)
        if signature == lastSignature && !shouldCaptureIcons {
            return
        }

        lastSignature = signature
        cacheByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        subject.send(merged)
    }

    func fetchIcons() async -> [DockIcon] {
        guard authState == .granted else { return [] }
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let scanned = scanner.scan(excludingBundleID: ownBundle, captureIcons: true)
        let now = Date()
        return scanned.map { entry in
            DockIcon(
                id: entry.item.id,
                source: .ax,
                symbolOrImage: "app",
                title: entry.item.title,
                bucket: .shelf,
                groupID: "External",
                lastUsedAt: now,
                rank: 0.4
            )
        }
    }

    func setHighFrequencyMode(_ enabled: Bool) {
        let nextCadence: AXScanCadence = enabled ? .active : .idle
        guard cadence != nextCadence else { return }
        cadence = nextCadence
        guard started else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: cadence.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer?.tolerance = cadence.tolerance
    }

    private func makeSignature(for items: [ExternalMenuBarItem]) -> String {
        items
            .sorted(by: { $0.id < $1.id })
            .map { "\($0.id)|\($0.title)|\(Int($0.frameInScreen.minX.rounded()))|\(Int($0.frameInScreen.width.rounded()))" }
            .joined(separator: "#")
    }
}

final class ManualIconSourceService: IconSourceProviding {
    func fetchIcons() async -> [DockIcon] {
        let now = Date()
        return [
            DockIcon(id: "wifi", source: .manual, symbolOrImage: "wifi", title: "Wi-Fi", bucket: .pinned, groupID: "Network", lastUsedAt: now, rank: 1.0),
            DockIcon(id: "battery", source: .manual, symbolOrImage: "battery.100", title: "Battery", bucket: .pinned, groupID: "System", lastUsedAt: now, rank: 0.95),
            DockIcon(id: "clock", source: .manual, symbolOrImage: "clock", title: "Clock", bucket: .pinned, groupID: "System", lastUsedAt: now, rank: 0.9),
            DockIcon(id: "sound", source: .manual, symbolOrImage: "speaker.wave.2", title: "Sound", bucket: .shelf, groupID: "Audio", lastUsedAt: now, rank: 0.65),
            DockIcon(id: "vpn", source: .manual, symbolOrImage: "lock.shield", title: "VPN", bucket: .shelf, groupID: "Network", lastUsedAt: now, rank: 0.45),
            DockIcon(id: "terminal", source: .manual, symbolOrImage: "terminal", title: "Terminal", bucket: .shelf, groupID: "Dev", lastUsedAt: now, rank: 0.55),
            DockIcon(id: "music", source: .manual, symbolOrImage: "music.note", title: "Music", bucket: .shelf, groupID: "Media", lastUsedAt: now, rank: 0.6)
        ]
    }
}

final class RunningAppIconSourceService: IconSourceProviding {
    func fetchIcons() async -> [DockIcon] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let now = Date()
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular else { return false }
                guard app.bundleIdentifier != ownBundleID else { return false }
                guard app.isFinishedLaunching else { return false }
                return app.icon != nil
            }
            .prefix(10)

        return apps.enumerated().map { index, app in
            DockIcon(
                id: "running.\(app.bundleIdentifier ?? "\(app.processIdentifier)")",
                source: .manual,
                symbolOrImage: "app",
                iconData: pngData(from: app.icon),
                title: app.localizedName ?? app.bundleIdentifier ?? "App",
                bucket: .shelf,
                groupID: "Running Apps",
                lastUsedAt: now,
                rank: 0.42 - (Double(index) * 0.01)
            )
        }
    }

    private func pngData(from image: NSImage?) -> Data? {
        guard let image else { return nil }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor
final class CompositeIconSourceService: IconSourceProviding, RunningAppIconControlling {
    private let manual: IconSourceProviding
    private let runningApps: IconSourceProviding
    private let ax: IconSourceProviding
    private let axProvider: ExternalIconProviding
    private var includeRunningApps = false

    init(
        manual: IconSourceProviding = ManualIconSourceService(),
        runningApps: IconSourceProviding = RunningAppIconSourceService(),
        ax: IconSourceProviding,
        axProvider: ExternalIconProviding
    ) {
        self.manual = manual
        self.runningApps = runningApps
        self.ax = ax
        self.axProvider = axProvider
    }

    func fetchIcons() async -> [DockIcon] {
        let manualIcons = await manual.fetchIcons()
        let runningIcons = includeRunningApps ? await runningApps.fetchIcons() : []
        let baseIcons = manualIcons + runningIcons
        guard axProvider.authState == .granted else {
            let dedupedBase = Dictionary(grouping: baseIcons, by: \.id).compactMap { $0.value.first }
            return dedupedBase
        }
        let axIcons = await ax.fetchIcons()
        let deduped = Dictionary(grouping: baseIcons + axIcons, by: \.id).compactMap { $0.value.first }
        return deduped
    }

    func setIncludeRunningApps(_ enabled: Bool) {
        includeRunningApps = enabled
    }
}
