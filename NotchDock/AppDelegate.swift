import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayWindowController?
    private var statusBarController: StatusBarController?
    private let hotkeyService = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnitTests else {
            return
        }
        let viewModel = NotchDockViewModel.shared
        let overlay = OverlayWindowController(viewModel: viewModel, geometry: NotchGeometryCalculator())
        self.overlayController = overlay
        self.statusBarController = StatusBarController(viewModel: viewModel, overlayController: overlay)
        hotkeyService.bind(to: viewModel)
        viewModel.requestExternalPermission()
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
