import Combine
import CoreGraphics
import XCTest
@testable import MacMenubar

final class ExternalHiddenShelfTests: XCTestCase {
    private var metricsProvider: HiddenShelfMetricsProvider!
    private var mediaProvider: HiddenShelfMediaProvider!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        metricsProvider = HiddenShelfMetricsProvider()
        mediaProvider = HiddenShelfMediaProvider()
        defaultsSuiteName = "tests.macmenubar.hidden-shelf.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = nil
        defaults = nil
        metricsProvider = nil
        mediaProvider = nil
        super.tearDown()
    }

    @MainActor
    func testHiddenShelfItemsArePublishedWhenVisibleListIsEmpty() {
        let externalProvider = HiddenShelfExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        let hidden = makeItem(id: "h1", x: 1400, shelfState: .hidden)
        externalProvider.pushHidden(items: [hidden])
        pumpMainRunLoop()

        XCTAssertEqual(viewModel.externalHiddenShelfItems.map(\.id), ["h1"])
        XCTAssertTrue(viewModel.externalStatusSummary.contains("HiddenShelf 1"))
    }

    @MainActor
    func testStaleHiddenBadgeStateIsPreserved() {
        let externalProvider = HiddenShelfExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        let stale = makeItem(id: "stale", x: 1200, shelfState: .staleHidden)
        externalProvider.pushHidden(items: [stale])
        pumpMainRunLoop()

        XCTAssertEqual(viewModel.externalHiddenShelfItems.first?.shelfState, .staleHidden)
    }

    @MainActor
    func testMirrorOnlyModeAndRefreshCanClearHiddenShelf() {
        let externalProvider = HiddenShelfExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        let hidden = makeItem(id: "h2", x: 1300, shelfState: .hidden)
        externalProvider.pushHidden(items: [hidden])
        pumpMainRunLoop()

        viewModel.setExternalItemMode(itemID: "h2", mode: .mirrorOnly)
        externalProvider.pushHidden(items: [])
        pumpMainRunLoop()

        XCTAssertTrue(viewModel.externalHiddenShelfItems.isEmpty)
    }

    private func makeItem(id: String, x: CGFloat, shelfState: ExternalShelfState) -> ExternalMenuBarItem {
        ExternalMenuBarItem(
            id: id,
            ownerBundleID: "com.example.\(id)",
            displayName: "Item \(id)",
            frameInScreen: CGRect(x: x, y: 860, width: 24, height: 16),
            isVisibleInSystemBar: false,
            supportsPressAction: true,
            iconPNGData: nil,
            lastSeenAt: .now,
            lastInteractionAt: .distantPast,
            shelfState: shelfState
        )
    }

    @MainActor
    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

private final class HiddenShelfMetricsProvider: MetricsProviding {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<SystemMetrics, Never>(.zero)

    func start() {}
    func stop() {}
}

private final class HiddenShelfMediaProvider: MediaProviding {
    var mediaStatePublisher: AnyPublisher<MediaState, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<MediaState, Never>(.unknown)

    func start() {}
    func stop() {}
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
}

@MainActor
private final class HiddenShelfExternalProvider: ExternalMenuBarProviding {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    var hiddenShelfPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        hiddenSubject.eraseToAnyPublisher()
    }

    var modeResult = ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: nil)

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let hiddenSubject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])

    func start() {}
    func stop() {}
    func refresh() {}

    func pushHidden(items: [ExternalMenuBarItem]) {
        hiddenSubject.send(items)
    }

    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult {
        modeResult
    }

    func revealHiddenItem(_ itemID: String) -> Bool {
        true
    }

    func performPrimaryAction(for itemID: String) -> Bool {
        true
    }

    func currentAuthState() -> MirrorAuthState {
        .granted
    }

    func requestPermission() -> MirrorAuthState {
        .granted
    }

    func openSystemSettings() {}
}
