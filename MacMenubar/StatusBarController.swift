import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let viewModel: MenuBarViewModel
    private let panelController: NotchPanelController
    private let dropZoneController: NotchDropZoneController

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self.panelController = NotchPanelController(viewModel: viewModel)
        self.dropZoneController = NotchDropZoneController(viewModel: viewModel)

        configureStatusItem()
        bindViewModel()
        renderStatusTitle()
        rebuildMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.toolTip = "MacMenubar"
    }

    private func bindViewModel() {
        viewModel.$icons
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$spacing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusTitle()
            }
            .store(in: &cancellables)

        viewModel.$overflowIcons
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$externalOverflowItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$externalHiddenShelfItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderStatusTitle()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$externalItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$externalPreferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$externalLastOperationMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$lastReclaimedBytes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$mirrorAuthState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$layoutSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.panelController.refreshPosition()
                self?.dropZoneController.refreshPosition()
            }
            .store(in: &cancellables)

        viewModel.$isPanelEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.panelController.hide()
                }
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$isNotchDropZoneEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.dropZoneController.show()
                } else {
                    self?.dropZoneController.hide()
                }
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        viewModel.$notchDropState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dropZoneController.refreshPosition()
            }
            .store(in: &cancellables)

        viewModel.$isDropZoneHovered
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dropZoneController.refreshPosition()
            }
            .store(in: &cancellables)

        if viewModel.isNotchDropZoneEnabled {
            dropZoneController.show()
        } else {
            dropZoneController.hide()
        }
    }

    private func renderStatusTitle() {
        guard let button = statusItem.button else { return }
        let hasOverflow = !viewModel.externalOverflowItems.isEmpty || !viewModel.externalHiddenShelfItems.isEmpty || !viewModel.overflowIcons.isEmpty
        let symbolName: String
        if panelController.isShown {
            symbolName = "line.3.horizontal.circle.fill"
        } else if hasOverflow {
            symbolName = "line.3.horizontal.decrease.circle"
        } else {
            symbolName = "line.3.horizontal.circle"
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "MacMenubar"
        ) ?? NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "MacMenubar")
        image?.isTemplate = true
        button.image = image
        button.title = ""

        let overflowCount = viewModel.externalOverflowItems.count + viewModel.externalHiddenShelfItems.count + viewModel.overflowIcons.count
        if overflowCount > 0 {
            button.toolTip = "MacMenubar · Overflow \(overflowCount)"
        } else {
            button.toolTip = "MacMenubar"
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let toggleTitle = panelController.isShown ? "Hide Panel" : "Show Panel"
        let togglePanel = NSMenuItem(title: toggleTitle, action: #selector(togglePanel), keyEquivalent: "")
        togglePanel.isEnabled = viewModel.isPanelEnabled
        togglePanel.target = self
        menu.addItem(togglePanel)

        let toggleDropZone = NSMenuItem(
            title: viewModel.isNotchDropZoneEnabled ? "Disable Notch Drop Zone" : "Enable Notch Drop Zone",
            action: #selector(toggleDropZone),
            keyEquivalent: ""
        )
        toggleDropZone.target = self
        menu.addItem(toggleDropZone)

        menu.addItem(NSMenuItem.separator())

        let overflowMenu = NSMenu(title: "Overflow")
        if viewModel.overflowIcons.isEmpty {
            let empty = NSMenuItem(title: "No hidden smart icons", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            overflowMenu.addItem(empty)
        } else {
            for icon in viewModel.overflowIcons {
                let item = NSMenuItem(title: icon.title, action: #selector(promoteFromOverflow(_:)), keyEquivalent: "")
                item.representedObject = icon.id
                item.target = self
                overflowMenu.addItem(item)
            }
        }

        let overflowRoot = NSMenuItem(title: "Overflow", action: nil, keyEquivalent: "")
        menu.setSubmenu(overflowMenu, for: overflowRoot)
        menu.addItem(overflowRoot)

        let externalRoot = NSMenuItem(title: "External Overflow", action: nil, keyEquivalent: "")
        let externalMenu = NSMenu(title: "External Overflow")

        let stateLine = NSMenuItem(title: "AX: \(authStateLabel())", action: nil, keyEquivalent: "")
        stateLine.isEnabled = false
        externalMenu.addItem(stateLine)

        let summary = NSMenuItem(title: viewModel.externalStatusSummary, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        externalMenu.addItem(summary)

        let hideSummary = NSMenuItem(title: viewModel.externalHideStatsSummary, action: nil, keyEquivalent: "")
        hideSummary.isEnabled = false
        externalMenu.addItem(hideSummary)

        if !viewModel.externalLastOperationMessage.isEmpty {
            let lastResult = NSMenuItem(title: "Last: \(viewModel.externalLastOperationMessage)", action: nil, keyEquivalent: "")
            lastResult.isEnabled = false
            externalMenu.addItem(lastResult)
        }

        if viewModel.lastReclaimedBytes > 0 {
            let reclaimed = ByteCountFormatter.string(fromByteCount: viewModel.lastReclaimedBytes, countStyle: .file)
            let reclaimItem = NSMenuItem(title: "Last reclaimed: \(reclaimed)", action: nil, keyEquivalent: "")
            reclaimItem.isEnabled = false
            externalMenu.addItem(reclaimItem)
        }

        let refresh = NSMenuItem(title: "Refresh External Icons", action: #selector(refreshExternalIcons), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = viewModel.mirrorAuthState == .granted
        externalMenu.addItem(refresh)

        if viewModel.mirrorAuthState != .granted {
            let request = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAXPermission), keyEquivalent: "")
            request.target = self
            externalMenu.addItem(request)

            let open = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAXSettings), keyEquivalent: "")
            open.target = self
            externalMenu.addItem(open)
        }

        externalMenu.addItem(NSMenuItem.separator())

        if viewModel.externalOverflowItems.isEmpty && viewModel.externalHiddenShelfItems.isEmpty {
            let empty = NSMenuItem(title: "No external overflow or hidden shelf", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            externalMenu.addItem(empty)
        } else {
            if !viewModel.externalHiddenShelfItems.isEmpty {
                let shelfHeader = NSMenuItem(title: "Hidden Shelf", action: nil, keyEquivalent: "")
                shelfHeader.isEnabled = false
                externalMenu.addItem(shelfHeader)

                for item in viewModel.externalHiddenShelfItems {
                    let iconMenu = NSMenu(title: item.displayName)

                    let openItem = NSMenuItem(title: "Open \(item.displayName)", action: #selector(performExternalAction(_:)), keyEquivalent: "")
                    openItem.representedObject = item.id
                    openItem.target = self
                    iconMenu.addItem(openItem)

                    let mirrorOnly = NSMenuItem(title: "Mirror only", action: #selector(assignExternalMode(_:)), keyEquivalent: "")
                    mirrorOnly.representedObject = ExternalModeSelection(itemID: item.id, mode: .mirrorOnly)
                    mirrorOnly.target = self
                    iconMenu.addItem(mirrorOnly)

                    let statusTitle = item.shelfState == .staleHidden ? "State: stale-hidden" : "State: hidden"
                    let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
                    statusItem.isEnabled = false
                    iconMenu.addItem(statusItem)

                    let shelfPrefix = item.shelfState == .staleHidden ? "[S]" : "[H]"
                    let root = NSMenuItem(title: "\(shelfPrefix) \(item.displayName)", action: nil, keyEquivalent: "")
                    externalMenu.setSubmenu(iconMenu, for: root)
                    externalMenu.addItem(root)
                }

                externalMenu.addItem(NSMenuItem.separator())
            }

            if !viewModel.externalOverflowItems.isEmpty {
                let overflowHeader = NSMenuItem(title: "Overflow", action: nil, keyEquivalent: "")
                overflowHeader.isEnabled = false
                externalMenu.addItem(overflowHeader)
            }

            for item in viewModel.externalOverflowItems {
                let iconMenu = NSMenu(title: item.displayName)

                let openItem = NSMenuItem(title: "Open \(item.displayName)", action: #selector(performExternalAction(_:)), keyEquivalent: "")
                openItem.representedObject = item.id
                openItem.target = self
                iconMenu.addItem(openItem)

                let pinItem = NSMenuItem(title: viewModel.isExternalPinned(itemID: item.id) ? "Unpin" : "Pin", action: #selector(toggleExternalPinned(_:)), keyEquivalent: "")
                pinItem.representedObject = item.id
                pinItem.target = self
                iconMenu.addItem(pinItem)

                for mode in ExternalItemVisibilityMode.allCases {
                    let modeItem = NSMenuItem(title: mode.displayName, action: #selector(assignExternalMode(_:)), keyEquivalent: "")
                    modeItem.representedObject = ExternalModeSelection(itemID: item.id, mode: mode)
                    modeItem.state = viewModel.externalMode(for: item.id) == mode ? .on : .off
                    modeItem.target = self
                    iconMenu.addItem(modeItem)
                }

                if let reason = viewModel.externalDowngradeReason(for: item.id) {
                    let reasonItem = NSMenuItem(title: "Last downgrade: \(reason.rawValue)", action: nil, keyEquivalent: "")
                    reasonItem.isEnabled = false
                    iconMenu.addItem(reasonItem)
                }

                let root = NSMenuItem(title: "\(externalStatePrefix(for: item.id)) \(item.displayName)", action: nil, keyEquivalent: "")
                externalMenu.setSubmenu(iconMenu, for: root)
                externalMenu.addItem(root)
            }
        }

        menu.setSubmenu(externalMenu, for: externalRoot)
        menu.addItem(externalRoot)

        let groupsRoot = NSMenuItem(title: "Set Visibility Group", action: nil, keyEquivalent: "")
        let groupsMenu = NSMenu(title: "Set Visibility Group")
        for icon in viewModel.icons.sorted(by: { $0.priority > $1.priority }) {
            let iconMenu = NSMenu(title: icon.title)
            for group in VisibilityGroup.allCases {
                let item = NSMenuItem(title: group.displayName, action: #selector(assignGroup(_:)), keyEquivalent: "")
                item.representedObject = GroupSelection(iconID: icon.id, group: group)
                item.state = icon.group == group ? .on : .off
                item.target = self
                iconMenu.addItem(item)
            }
            let iconRoot = NSMenuItem(title: icon.title, action: nil, keyEquivalent: "")
            groupsMenu.setSubmenu(iconMenu, for: iconRoot)
            groupsMenu.addItem(iconRoot)
        }
        menu.setSubmenu(groupsMenu, for: groupsRoot)
        menu.addItem(groupsRoot)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        if event.type == .rightMouseUp {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
            return
        }

        togglePanel()
    }

    @objc private func togglePanel() {
        guard viewModel.isPanelEnabled else { return }
        panelController.toggle()
        renderStatusTitle()
        rebuildMenu()
    }

    @objc private func promoteFromOverflow(_ sender: NSMenuItem) {
        guard let iconID = sender.representedObject as? String else { return }
        viewModel.setIconGroup(id: iconID, group: .alwaysVisible)
        viewModel.registerInteraction(iconID: iconID)
    }

    @objc private func performExternalAction(_ sender: NSMenuItem) {
        guard let itemID = sender.representedObject as? String else { return }
        viewModel.performExternalItemPrimaryAction(itemID: itemID)
    }

    @objc private func assignExternalMode(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ExternalModeSelection else { return }
        viewModel.setExternalItemMode(itemID: selection.itemID, mode: selection.mode)
    }

    @objc private func toggleExternalPinned(_ sender: NSMenuItem) {
        guard let itemID = sender.representedObject as? String else { return }
        let next = !viewModel.isExternalPinned(itemID: itemID)
        viewModel.setExternalItemPinned(itemID: itemID, pinned: next)
    }

    @objc private func requestAXPermission() {
        viewModel.requestAXPermission()
    }

    @objc private func openAXSettings() {
        viewModel.openAXSettings()
    }

    @objc private func refreshExternalIcons() {
        viewModel.refreshExternalItems()
    }

    @objc private func toggleDropZone() {
        viewModel.isNotchDropZoneEnabled.toggle()
        if viewModel.isNotchDropZoneEnabled {
            dropZoneController.show()
        } else {
            dropZoneController.hide()
        }
        rebuildMenu()
    }

    @objc private func assignGroup(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? GroupSelection else { return }
        viewModel.setIconGroup(id: selection.iconID, group: selection.group)
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func authStateLabel() -> String {
        switch viewModel.mirrorAuthState {
        case .unknown:
            return "Unknown"
        case .denied:
            return "Denied"
        case .granted:
            return "Granted"
        }
    }

    private func externalStatePrefix(for itemID: String) -> String {
        switch viewModel.resolvedExternalState(for: itemID) {
        case .hiddenApplied:
            return "[H]"
        case .mirrorOnly:
            return "[M]"
        case .downgraded:
            return "[!]"
        }
    }
}

private struct GroupSelection {
    let iconID: String
    let group: VisibilityGroup
}

private struct ExternalModeSelection {
    let itemID: String
    let mode: ExternalItemVisibilityMode
}

@MainActor
private final class NotchPanelController {
    private let panel: NSPanel
    private let width: CGFloat = 430
    private let collapsedHeight: CGFloat = 38
    private let expandedHeight: CGFloat = 210
    private let viewModel: MenuBarViewModel

    private var cancellables = Set<AnyCancellable>()
    private(set) var isShown: Bool = false

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel

        let content = NotchPanelView(viewModel: viewModel)
            .frame(width: width - 20)

        let host = NSHostingController(rootView: content)

        panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: width, height: collapsedHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = host

        viewModel.$isPanelExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        updateFrame(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    func refreshPosition() {
        updateFrame(animated: true)
    }

    private func updateFrame(animated: Bool) {
        guard isShown else { return }
        let target = targetFrame()
        if animated {
            panel.animator().setFrame(target, display: true)
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func targetFrame() -> NSRect {
        let height = viewModel.isPanelExpanded ? expandedHeight : collapsedHeight
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: width, height: height)
        }

        let frame = screen.frame
        let visible = screen.visibleFrame
        let x = frame.midX - (width / 2)
        let y = visible.maxY - height - 6
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
private final class NotchDropZoneController {
    private let panel: NSPanel
    private let viewModel: MenuBarViewModel

    private let collapsedWidth: CGFloat = 180
    private let expandedWidth: CGFloat = 460
    private let collapsedHeight: CGFloat = 16
    private let expandedHeight: CGFloat = 176

    private(set) var isShown: Bool = false

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel

        let content = NotchDropZoneView(viewModel: viewModel)
            .frame(width: expandedWidth - 10)
        let host = NSHostingController(rootView: content)

        panel = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: collapsedWidth, height: collapsedHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = host
    }

    func show() {
        guard !isShown else {
            refreshPosition()
            return
        }
        isShown = true
        refreshPosition()
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    func refreshPosition() {
        guard isShown else { return }
        panel.setFrame(targetFrame(), display: true)
    }

    private var isExpanded: Bool {
        viewModel.isDropZoneHovered || viewModel.notchDropState != .idle
    }

    private func targetFrame() -> NSRect {
        let width = isExpanded ? expandedWidth : collapsedWidth
        let height = isExpanded ? expandedHeight : collapsedHeight
        guard let screen = NSScreen.main else {
            return NSRect(x: 120, y: 120, width: width, height: height)
        }

        let frame = screen.frame
        let visible = screen.visibleFrame
        let hasNotch = viewModel.layoutSnapshot.notchWidth > 0
        let anchor = HubAnchorCalculator.calculate(
            screenFrame: frame,
            visibleFrame: visible,
            hasNotch: hasNotch,
            hubHeight: height
        )
        let x = anchor.x - (width / 2)
        let y = anchor.y
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
