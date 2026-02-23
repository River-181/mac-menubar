import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: NotchDockViewModel
    private let overlayController: OverlayWindowController

    init(viewModel: NotchDockViewModel, overlayController: OverlayWindowController) {
        self.viewModel = viewModel
        self.overlayController = overlayController
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "capsule.portrait", accessibilityDescription: "NotchDock")
        button.target = self
        button.action = #selector(toggleDock)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleDock() {
        guard let event = NSApp.currentEvent else {
            overlayController.toggleExpand()
            return
        }
        if event.type == .rightMouseUp {
            openMenu()
        } else {
            overlayController.toggleExpand()
        }
    }

    private func openMenu() {
        let menu = NSMenu(title: "NotchDock")
        menu.addItem(withTitle: "Toggle Expand", action: #selector(toggleExpandMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Toggle Workspace", action: #selector(toggleWorkspaceMenuAction), keyEquivalent: "")
        menu.addItem(.separator())

        let overflowSummary = NSMenuItem(title: "Overflow: \(viewModel.overflowIcons.count)", action: nil, keyEquivalent: "")
        overflowSummary.isEnabled = false
        menu.addItem(overflowSummary)

        let compactSummary = NSMenuItem(title: "Compact mode: \(viewModel.effectiveCompactMode ? "On" : "Off")", action: nil, keyEquivalent: "")
        compactSummary.isEnabled = false
        menu.addItem(compactSummary)

        let perfSummary = NSMenuItem(title: "Perf: \(viewModel.perfSnapshotSummary)", action: nil, keyEquivalent: "")
        perfSummary.isEnabled = false
        menu.addItem(perfSummary)

        if let toast = viewModel.dropToast {
            let message = NSMenuItem(title: toast.message, action: nil, keyEquivalent: "")
            message.isEnabled = false
            menu.addItem(message)
        }

        let copyPerfItem = NSMenuItem(title: "Copy Perf Snapshot", action: #selector(copyPerfSnapshot), keyEquivalent: "")
        copyPerfItem.target = self
        menu.addItem(copyPerfItem)
        let resetPerfItem = NSMenuItem(title: "Reset Perf Counters", action: #selector(resetPerfCounters), keyEquivalent: "")
        resetPerfItem.target = self
        menu.addItem(resetPerfItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit NotchDock", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleExpandMenuAction() {
        viewModel.toggleExpand()
    }

    @objc private func toggleWorkspaceMenuAction() {
        viewModel.toggleWorkspace(trigger: .hotkey)
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func copyPerfSnapshot() {
        let snapshot = viewModel.perfSnapshotSummary
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshot, forType: .string)
    }

    @objc private func resetPerfCounters() {
        viewModel.resetPerfSnapshot()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
