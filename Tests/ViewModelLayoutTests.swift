import AppKit
import Combine
import XCTest
@testable import MacMenubar

final class ViewModelLayoutTests: XCTestCase {
    private var metricsProvider: MockMetricsProvider!
    private var mediaProvider: MockMediaProvider!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        metricsProvider = MockMetricsProvider()
        mediaProvider = MockMediaProvider()
        defaultsSuiteName = "tests.macmenubar.\(UUID().uuidString)"
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
    func testSmartHideMovesToOverflowWhenSideBudgetIsTight() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.recalculateLayout(
            snapshot: LayoutSnapshot(
                screenWidth: 1512,
                notchWidth: 160,
                reservedCenterWidth: 208,
                sideBudget: 180,
                spacing: 8,
                fullscreenLike: false
            )
        )

        let music = viewModel.icons.first(where: { $0.id == "music" })
        XCTAssertEqual(music?.isVisible, false)
        XCTAssertEqual(viewModel.overflowIcons.map(\.id), ["music"])
    }

    @MainActor
    func testSmartHideVisibleWhenEnoughSpace() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.recalculateLayout(
            snapshot: LayoutSnapshot(
                screenWidth: 1512,
                notchWidth: 160,
                reservedCenterWidth: 208,
                sideBudget: 420,
                spacing: 8,
                fullscreenLike: false
            )
        )

        let music = viewModel.icons.first(where: { $0.id == "music" })
        XCTAssertEqual(music?.isVisible, true)
        XCTAssertTrue(viewModel.overflowIcons.isEmpty)
    }

    @MainActor
    func testSettingHiddenGroupForcesInvisible() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.setIconGroup(id: "music", group: .hidden)

        let music = viewModel.icons.first(where: { $0.id == "music" })
        XCTAssertEqual(music?.group, .hidden)
        XCTAssertEqual(music?.isVisible, false)
    }

    @MainActor
    func testAdaptiveAutoUsesCompactWhenNotchExists() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            XCTFail("Missing screen context for test")
            return
        }

        viewModel.setNotchDefaultPolicy(.adaptiveAuto)
        viewModel.applyDisplayPolicy(for: screen, hasNotch: true)

        XCTAssertEqual(viewModel.notchDisplayMode, .hideNotchLike)
    }

    @MainActor
    func testAdaptiveAutoUsesRespectWhenNoNotch() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            XCTFail("Missing screen context for test")
            return
        }

        viewModel.setNotchDefaultPolicy(.adaptiveAuto)
        viewModel.applyDisplayPolicy(for: screen, hasNotch: false)

        XCTAssertEqual(viewModel.notchDisplayMode, .respectNotch)
    }

    @MainActor
    func testForcedPolicyOverridesAdaptive() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            XCTFail("Missing screen context for test")
            return
        }

        viewModel.setNotchDefaultPolicy(.alwaysRespect)
        viewModel.applyDisplayPolicy(for: screen, hasNotch: true)
        XCTAssertEqual(viewModel.notchDisplayMode, .respectNotch)

        viewModel.setNotchDefaultPolicy(.alwaysCompact)
        viewModel.applyDisplayPolicy(for: screen, hasNotch: false)
        XCTAssertEqual(viewModel.notchDisplayMode, .hideNotchLike)
    }

    @MainActor
    func testCompactSpacingIsClamped() {
        let externalProvider = MockExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.setNotchDisplayMode(.hideNotchLike)
        viewModel.recalculateLayout(
            snapshot: LayoutSnapshot(
                screenWidth: 1600,
                notchWidth: 170,
                reservedCenterWidth: 220,
                sideBudget: 1200,
                spacing: 14,
                fullscreenLike: false
            )
        )

        XCTAssertGreaterThanOrEqual(viewModel.layoutSnapshot.spacing, 3.5)
        XCTAssertLessThanOrEqual(viewModel.layoutSnapshot.spacing, 9.5)
    }
}

private final class MockMetricsProvider: MetricsProviding {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<SystemMetrics, Never>(.zero)

    func start() {}
    func stop() {}
}

private final class MockMediaProvider: MediaProviding {
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
private final class MockExternalProvider: ExternalMenuBarProviding {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    var hiddenShelfPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        hiddenSubject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let hiddenSubject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])

    func start() {}
    func stop() {}
    func refresh() {}

    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult {
        ExternalModeUpdateResult(effectiveMode: mode, downgradeReason: nil)
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
