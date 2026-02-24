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
        let toggle = NSMenuItem(title: "Toggle Overlay", action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let overflow = NSMenuItem(title: "Overflow Icons: \(viewModel.overflowIcons.count)", action: nil, keyEquivalent: "")
        overflow.isEnabled = false
        menu.addItem(overflow)

        let perf = NSMenuItem(title: viewModel.perfSummaryText, action: nil, keyEquivalent: "")
        perf.isEnabled = false
        menu.addItem(perf)

        if let toast = viewModel.toast {
            let toastItem = NSMenuItem(title: toast.message, action: nil, keyEquivalent: "")
            toastItem.isEnabled = false
            menu.addItem(toastItem)
        }

        menu.addItem(.separator())
        let resetPerf = NSMenuItem(title: "Reset Perf Counters", action: #selector(resetPerfCounters), keyEquivalent: "")
        resetPerf.target = self
        menu.addItem(resetPerf)

        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit NotchDock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleOverlay() {
        overlayController.toggleExpand()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func resetPerfCounters() {
        viewModel.resetPerfSnapshot()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
