import Combine
import CoreGraphics
import XCTest
@testable import MacMenubar

final class ExternalIconPolicyTests: XCTestCase {
    private var metricsProvider: TestMetricsProvider!
    private var mediaProvider: TestMediaProvider!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        metricsProvider = TestMetricsProvider()
        mediaProvider = TestMediaProvider()
        defaultsSuiteName = "tests.macmenubar.external.\(UUID().uuidString)"
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
    func testExternalItemsSplitIntoVisibleAndOverflowByBudget() {
        let externalProvider = TestExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.recalculateLayout(
            snapshot: LayoutSnapshot(
                screenWidth: 1512,
                notchWidth: 164,
                reservedCenterWidth: 212,
                sideBudget: 180,
                spacing: 8,
                fullscreenLike: false
            )
        )

        externalProvider.push(items: [
            makeItem(id: "a", x: 1450),
            makeItem(id: "b", x: 1410),
            makeItem(id: "c", x: 1370)
        ])
        pumpMainRunLoop()

        XCTAssertEqual(viewModel.externalVisibleItems.map(\.id), ["a", "b"])
        XCTAssertEqual(viewModel.externalOverflowItems.map(\.id), ["c"])
    }

    @MainActor
    func testHideDowngradesToMirrorOnlyOnUnsupportedItem() {
        let externalProvider = TestExternalProvider()
        externalProvider.setModeResult = ExternalModeUpdateResult(
            effectiveMode: .mirrorOnly,
            downgradeReason: .unsupportedAttribute
        )

        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.setExternalItemMode(itemID: "x", mode: .mirrorAndHide)

        XCTAssertEqual(viewModel.externalMode(for: "x"), .mirrorOnly)
        XCTAssertEqual(viewModel.externalDowngradeReason(for: "x"), .unsupportedAttribute)
    }

    @MainActor
    func testPinningPrioritizesVisibilityOrder() {
        let externalProvider = TestExternalProvider()
        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            defaults: defaults
        )

        viewModel.recalculateLayout(
            snapshot: LayoutSnapshot(
                screenWidth: 1512,
                notchWidth: 164,
                reservedCenterWidth: 212,
                sideBudget: 180,
                spacing: 8,
                fullscreenLike: false
            )
        )

        externalProvider.push(items: [
            makeItem(id: "a", x: 1450),
            makeItem(id: "b", x: 1410),
            makeItem(id: "c", x: 1370)
        ])
        pumpMainRunLoop()
        viewModel.setExternalItemPinned(itemID: "c", pinned: true)
        pumpMainRunLoop()

        XCTAssertEqual(viewModel.externalVisibleItems.first?.id, "c")
    }

    private func makeItem(id: String, x: CGFloat) -> ExternalMenuBarItem {
        ExternalMenuBarItem(
            id: id,
            ownerBundleID: "com.example.\(id)",
            displayName: "Item \(id)",
            frameInScreen: CGRect(x: x, y: 860, width: 50, height: 20),
            isVisibleInSystemBar: true,
            supportsPressAction: true,
            iconPNGData: nil,
            lastSeenAt: .now,
            lastInteractionAt: .distantPast,
            shelfState: .none
        )
    }

    @MainActor
    private func pumpMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}

private final class TestMetricsProvider: MetricsProviding {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<SystemMetrics, Never>(.zero)

    func start() {}
    func stop() {}
}

private final class TestMediaProvider: MediaProviding {
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
private final class TestExternalProvider: ExternalMenuBarProviding {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        subject.eraseToAnyPublisher()
    }

    var hiddenShelfPublisher: AnyPublisher<[ExternalMenuBarItem], Never> {
        hiddenSubject.eraseToAnyPublisher()
    }

    var authState: MirrorAuthState = .granted
    var setModeResult = ExternalModeUpdateResult(effectiveMode: .mirrorOnly, downgradeReason: nil)

    private let subject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])
    private let hiddenSubject = CurrentValueSubject<[ExternalMenuBarItem], Never>([])

    func start() {}
    func stop() {}
    func refresh() {}

    func push(items: [ExternalMenuBarItem]) {
        subject.send(items)
    }

    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult {
        setModeResult
    }

    func revealHiddenItem(_ itemID: String) -> Bool {
        true
    }

    func performPrimaryAction(for itemID: String) -> Bool {
        true
    }

    func currentAuthState() -> MirrorAuthState {
        authState
    }

    func requestPermission() -> MirrorAuthState {
        authState
    }

    func openSystemSettings() {}
}
