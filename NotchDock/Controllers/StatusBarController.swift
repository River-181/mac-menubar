import ApplicationServices
import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: NotchDockViewModel
    private let overlayController: OverlayWindowController

    init(viewModel: NotchDockViewModel, overlayController: OverlayWindowController) {
        self.viewModel = viewModel
        self.overlayController = overlayController
        super.init()
        configure()
    }

    private func configure() {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "capsule.lefthalf.filled", accessibilityDescription: "NotchDock")
        button.target = self
        button.action = #selector(handleStatusClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusClick() {
        guard let event = NSApp.currentEvent else {
            overlayController.toggleExpand()
            return
        }
        if event.type == .rightMouseUp {
            openContextMenu()
        } else {
            overlayController.toggleExpand()
        }
    }

    private func openContextMenu() {
        let menu = NSMenu(title: "NotchDock")
        // Disable automatic enabling so we can manually control item states.
        menu.autoenablesItems = false

        let toggle = NSMenuItem(title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = true
        menu.addItem(toggle)
        menu.addItem(.separator())

        let perf = NSMenuItem(title: viewModel.perfSummaryText, action: nil, keyEquivalent: "")
        perf.isEnabled = false
        menu.addItem(perf)

        menu.addItem(.separator())

        let undo = NSMenuItem(title: "Undo Last Action", action: #selector(undoLastAction), keyEquivalent: "")
        undo.target = self
        undo.isEnabled = viewModel.canUndoDangerousAction
        menu.addItem(undo)

        let resetPerf = NSMenuItem(title: "Reset Perf Counters", action: #selector(resetPerfCounters), keyEquivalent: "")
        resetPerf.target = self
        resetPerf.isEnabled = true
        menu.addItem(resetPerf)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = true
        menu.addItem(settings)

        // Only nudge the user if accessibility hasn't been granted yet.
        if !AXIsProcessTrusted() {
            let accessibility = NSMenuItem(
                title: "Enable Global Shortcuts\u{2026}",
                action: #selector(openAccessibilityPrefs),
                keyEquivalent: ""
            )
            accessibility.target = self
            accessibility.isEnabled = true
            menu.addItem(accessibility)
        }

        let quit = NSMenuItem(title: "Quit NotchDock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleOverlay() {
        overlayController.toggleExpand()
    }

    @objc private func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.showSettingsWindow(_:)), to: NSApp.delegate, from: nil)
    }

    @objc private func undoLastAction() {
        Task { @MainActor in
            await viewModel.undoLastDangerousAction()
        }
    }

    @objc private func resetPerfCounters() {
        viewModel.resetPerfSnapshot()
    }

    @objc private func openAccessibilityPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
