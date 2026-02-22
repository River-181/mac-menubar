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
