import AppKit
import Combine

final class NotchManager {
    private let viewModel: MenuBarViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    func startMonitoring() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.recalculate() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.recalculate() }
            .store(in: &cancellables)

        recalculate()
    }

    private func recalculate() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let safe = screen.safeAreaInsets
        let notchWidth = max(0, frame.width - (safe.left + safe.right))
        let notchPadding: CGFloat = 24
        let reservedCenter = notchWidth + notchPadding * 2
        let available = max(220, frame.width - reservedCenter)
        let activeAppIsFullscreen = NSWorkspace.shared.frontmostApplication?.activationPolicy() == .regular
            && frame.equalTo(screen.visibleFrame) == false
        viewModel.recalculateLayout(availableWidth: available / 2, activeAppIsFullscreen: activeAppIsFullscreen)
    }
}
