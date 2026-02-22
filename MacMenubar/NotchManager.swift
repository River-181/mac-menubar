import AppKit

struct HubAnchorCalculator {
    static func calculate(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        hasNotch: Bool,
        hubHeight: CGFloat
    ) -> CGPoint {
        let centerX = hasNotch ? screenFrame.midX : visibleFrame.midX
        let topPadding: CGFloat = hasNotch ? 2 : 6
        let topY = visibleFrame.maxY - hubHeight - topPadding
        return CGPoint(x: centerX, y: topY)
    }
}

struct NotchLayoutCalculator {
    static func calculate(
        screenWidth: CGFloat,
        safeLeft: CGFloat,
        safeRight: CGFloat,
        fullscreenLike: Bool,
        centerPadding: CGFloat = 24,
        minSideWidth: CGFloat = 220
    ) -> LayoutSnapshot {
        let notchWidth = max(0, screenWidth - (safeLeft + safeRight))
        let reservedCenterWidth = notchWidth + (centerPadding * 2)
        let sideBudget = max(minSideWidth, (screenWidth - reservedCenterWidth) / 2)

        let baseSpacing = clamp(sideBudget / 180, min: 6, max: 14)
        let spacing: CGFloat
        if fullscreenLike {
            spacing = max(4, baseSpacing * 0.72)
        } else {
            spacing = baseSpacing
        }

        return LayoutSnapshot(
            screenWidth: screenWidth,
            notchWidth: notchWidth,
            reservedCenterWidth: reservedCenterWidth,
            sideBudget: sideBudget,
            spacing: spacing,
            fullscreenLike: fullscreenLike
        )
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}

@MainActor
final class NotchManager {
    private let viewModel: MenuBarViewModel
    private var observerTokens: [NSObjectProtocol] = []

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    func startMonitoring() {
        stopMonitoring()

        let center = NotificationCenter.default
        observerTokens.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.recalculate()
                }
            }
        )

        observerTokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.recalculate()
                }
            }
        )

        recalculate()
    }

    func stopMonitoring() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    func recalculate() {
        guard let screen = NSScreen.main else { return }

        let frame = screen.frame
        let safeInsets = screen.safeAreaInsets
        let fullscreenLike = isFullscreenLike(screen: screen)

        let snapshot = NotchLayoutCalculator.calculate(
            screenWidth: frame.width,
            safeLeft: safeInsets.left,
            safeRight: safeInsets.right,
            fullscreenLike: fullscreenLike
        )
        viewModel.recalculateLayout(snapshot: snapshot)
        viewModel.refreshExternalItems()
    }

    private func isFullscreenLike(screen: NSScreen) -> Bool {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let menuBarConsumedHeight = frame.height - visible.height
        return menuBarConsumedHeight < 8
    }
}
