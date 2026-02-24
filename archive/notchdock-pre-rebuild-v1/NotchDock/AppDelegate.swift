import AppKit
import Sentry
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var overlayController: OverlayWindowController?
    private var statusBarController: StatusBarController?
    private var settingsWindow: NSWindow?
    private let hotkeyService = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningUnitTests else {
            return
        }
        configureSentryIfPossible()
        let viewModel = NotchDockViewModel.shared
        let overlay = OverlayWindowController(viewModel: viewModel, geometry: NotchGeometryCalculator())
        self.overlayController = overlay
        self.statusBarController = StatusBarController(viewModel: viewModel, overlayController: overlay)
        hotkeyService.bind(to: viewModel)
        viewModel.requestExternalPermission()
    }

    @objc func openSettingsWindow(_ sender: Any?) {
        _ = sender
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(viewModel: NotchDockViewModel.shared)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "NotchDock Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 500, height: 620))
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == settingsWindow else {
            return
        }
        settingsWindow = nil
    }

    private var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func configureSentryIfPossible() {
        let dsn = (Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !dsn.isEmpty else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = "development"
            options.enableAppHangTracking = true
            options.enableAutoSessionTracking = true
        }
    }
}
