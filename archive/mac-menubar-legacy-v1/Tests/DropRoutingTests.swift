import Combine
import CoreGraphics
import XCTest
@testable import MacMenubar

final class DropRoutingTests: XCTestCase {
    private var metricsProvider: DropMetricsProvider!
    private var mediaProvider: DropMediaProvider!
    private var fileActionProvider: DropFileActionProvider!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        metricsProvider = DropMetricsProvider()
        mediaProvider = DropMediaProvider()
        fileActionProvider = DropFileActionProvider()
        defaultsSuiteName = "tests.macmenubar.drop.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaultsSuiteName = nil
        defaults = nil
        fileActionProvider = nil
        mediaProvider = nil
        metricsProvider = nil
        super.tearDown()
    }

    @MainActor
    func testImageDropRoutesToRecommendedOptimizeAction() {
        let externalProvider = DropExternalProvider()
        let imageURL = URL(fileURLWithPath: "/tmp/sample.png")
        fileActionProvider.classification = DropClassification(
            kind: .images,
            descriptors: [
                DroppedFileDescriptor(
                    id: imageURL.path,
                    url: imageURL,
                    utType: "public.png",
                    fileName: "sample.png",
                    fileSize: 0
                )
            ],
            recommendedAction: .optimizeImages,
            secondaryActions: [.resizeImages, .imageToPDF]
        )

        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            fileActionService: fileActionProvider,
            defaults: defaults
        )

        viewModel.handleDroppedItems([imageURL])
        XCTAssertEqual(viewModel.notchDropState, .dropCommit(.optimizeImages))

        let expectation = expectation(description: "recommended action executes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(self.fileActionProvider.lastExecuteAction, .optimizeImages)
            XCTAssertEqual(viewModel.notchDropState, .success)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testPreferredDropActionOverridesRecommended() {
        let externalProvider = DropExternalProvider()
        let imageURL = URL(fileURLWithPath: "/tmp/sample.png")
        fileActionProvider.classification = DropClassification(
            kind: .images,
            descriptors: [
                DroppedFileDescriptor(
                    id: imageURL.path,
                    url: imageURL,
                    utType: "public.png",
                    fileName: "sample.png",
                    fileSize: 0
                )
            ],
            recommendedAction: .optimizeImages,
            secondaryActions: [.resizeImages, .imageToPDF]
        )

        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            fileActionService: fileActionProvider,
            defaults: defaults
        )

        viewModel.handleDroppedItems([imageURL], preferredAction: .imageToPDF)
        XCTAssertEqual(viewModel.notchDropState, .dropCommit(.imageToPDF))

        let expectation = expectation(description: "preferred action executes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(self.fileActionProvider.lastExecuteAction, .imageToPDF)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testDragSessionTransitionsThroughMagnetAndDropCommit() {
        let externalProvider = DropExternalProvider()
        let imageURL = URL(fileURLWithPath: "/tmp/sample.png")
        fileActionProvider.classification = DropClassification(
            kind: .images,
            descriptors: [
                DroppedFileDescriptor(
                    id: imageURL.path,
                    url: imageURL,
                    utType: "public.png",
                    fileName: "sample.png",
                    fileSize: 0
                )
            ],
            recommendedAction: .optimizeImages,
            secondaryActions: []
        )

        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            fileActionService: fileActionProvider,
            defaults: defaults
        )

        viewModel.beginDragSession(with: [imageURL])
        XCTAssertEqual(viewModel.notchDropState, .preheat)

        viewModel.updateDragTarget(.optimizeImages)
        XCTAssertEqual(viewModel.notchDropState, .magnetFocus(.optimizeImages))

        viewModel.handleDroppedItems([imageURL], preferredAction: .optimizeImages)
        XCTAssertEqual(viewModel.notchDropState, .dropCommit(.optimizeImages))

        let expectation = expectation(description: "drop commit completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(viewModel.notchDropState, .success)
            XCTAssertFalse(viewModel.dragSession.isFileDrag)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testFastDragReducesMagnetSnapStrength() {
        let externalProvider = DropExternalProvider()
        let imageURL = URL(fileURLWithPath: "/tmp/sample.png")
        fileActionProvider.classification = DropClassification(
            kind: .images,
            descriptors: [
                DroppedFileDescriptor(
                    id: imageURL.path,
                    url: imageURL,
                    utType: "public.png",
                    fileName: "sample.png",
                    fileSize: 0
                )
            ],
            recommendedAction: .optimizeImages,
            secondaryActions: []
        )

        let viewModel = MenuBarViewModel(
            metricsProvider: metricsProvider,
            mediaProvider: mediaProvider,
            externalProvider: externalProvider,
            fileActionService: fileActionProvider,
            defaults: defaults
        )

        viewModel.beginDragSession(with: [imageURL])
        viewModel.updateDragDynamics(
            DragDynamics(
                velocity: CGPoint(x: 1800, y: 0),
                acceleration: CGPoint(x: 0, y: 0),
                lastPoint: .zero,
                lastTimestamp: 1
            )
        )

        XCTAssertLessThan(viewModel.magnetSnapStrength, 0.6)
        viewModel.endDragSession()
        XCTAssertEqual(viewModel.magnetSnapStrength, 1, accuracy: 0.001)
    }

    func testHubAnchorUsesVisibleMidXOnNonNotchDisplay() {
        let anchor = HubAnchorCalculator.calculate(
            screenFrame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1400),
            hasNotch: false,
            hubHeight: 16
        )

        XCTAssertEqual(anchor.x, 1720, accuracy: 0.001)
        XCTAssertEqual(anchor.y, 1378, accuracy: 0.001)
    }
}

private final class DropMetricsProvider: MetricsProviding {
    var metricsPublisher: AnyPublisher<SystemMetrics, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = CurrentValueSubject<SystemMetrics, Never>(.zero)

    func start() {}
    func stop() {}
}

private final class DropMediaProvider: MediaProviding {
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
private final class DropExternalProvider: ExternalMenuBarProviding {
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

    func revealHiddenItem(_ itemID: String) -> Bool { true }

    func performPrimaryAction(for itemID: String) -> Bool { true }
    func currentAuthState() -> MirrorAuthState { .granted }
    func requestPermission() -> MirrorAuthState { .granted }
    func openSystemSettings() {}
}

private final class DropFileActionProvider: FileActionExecuting {
    var classification = DropClassification(kind: .unsupported, descriptors: [], recommendedAction: nil, secondaryActions: [])
    var lastExecuteAction: NotchActionKind?

    func classify(urls: [URL]) -> DropClassification {
        classification
    }

    func availableActions(for kind: DropContentKind) -> [NotchActionKind] {
        switch kind {
        case .images:
            return [.optimizeImages, .resizeImages, .imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash]
        case .pdfs:
            return [.optimizePDFKeepText, .pdfToImages, .compressZip, .sendToWorkbench, .moveToTrash]
        case .zipArchives:
            return [.extractZip, .compressZip, .sendToWorkbench, .moveToTrash]
        case .mixed:
            return [.compressZip, .sendToWorkbench, .moveToTrash]
        case .unsupported:
            return [.sendToWorkbench, .compressZip, .moveToTrash]
        }
    }

    func execute(action: NotchActionKind, inputs: [DroppedFileDescriptor], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult {
        lastExecuteAction = action
        return ActionExecutionResult(action: action, outputs: [], message: "ok", undoToken: nil, spaceDeltaBytes: 0, warnings: [])
    }

    func undo(token: UndoToken) -> Bool { true }

    func workbenchFolderURL() -> URL {
        URL(fileURLWithPath: "/tmp")
    }
}
