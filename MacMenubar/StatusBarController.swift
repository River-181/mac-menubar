import AppKit
import SwiftUI

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = NSPopover()
    private let viewModel: MenuBarViewModel

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        configureStatusItem()
        configurePanel()
        setupTimerFeeds()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = "◉"
        button.action = #selector(togglePanel)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func configurePanel() {
        panel.behavior = .transient
        panel.animates = true
        panel.contentSize = NSSize(width: 380, height: 120)
        panel.contentViewController = NSHostingController(rootView: NotchPanelView(viewModel: viewModel))
    }

    @objc private func togglePanel() {
        guard viewModel.isPanelEnabled, let button = statusItem.button else { return }
        if panel.isShown {
            panel.performClose(nil)
        } else {
            panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func setupTimerFeeds() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.viewModel.batteryPercentage = Int.random(in: 25...100)
            self?.viewModel.cpuUsage = Double.random(in: 8...55)
            self?.viewModel.memoryUsage = Double.random(in: 20...78)
            self?.viewModel.todayEvents = ["Standup 10:30", "Design review 15:00"]
        }
    }
}
