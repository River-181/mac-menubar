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
    private var lastExternalRefreshAt: Date = .distantPast
    private let appActivationRefreshInterval: TimeInterval = 3.0

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
                    self?.recalculate(forceExternalRefresh: true)
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
                    self?.recalculate(forceExternalRefresh: false)
                }
            }
        )

        recalculate(forceExternalRefresh: true)
    }

    func stopMonitoring() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    func recalculate(forceExternalRefresh: Bool = false) {
        guard let screen = NSScreen.main else { return }

        let frame = screen.frame
        let safeInsets = screen.safeAreaInsets
        let fullscreenLike = isFullscreenLike(screen: screen)
        var snapshot = NotchLayoutCalculator.calculate(
            screenWidth: frame.width,
            safeLeft: safeInsets.left,
            safeRight: safeInsets.right,
            fullscreenLike: fullscreenLike
        )
        let hasNotch = snapshot.notchWidth > 0
        viewModel.applyDisplayPolicy(for: screen, hasNotch: hasNotch)
        snapshot.effectiveCompactMode = viewModel.notchDisplayMode == .hideNotchLike
        snapshot.effectiveSpacingMultiplier = spacingMultiplier(
            compactMode: snapshot.effectiveCompactMode,
            fullscreenLike: fullscreenLike
        )
        viewModel.recalculateLayout(snapshot: snapshot)
        if shouldRefreshExternal(force: forceExternalRefresh) {
            viewModel.refreshExternalItems()
            lastExternalRefreshAt = .now
        }
    }

    private func isFullscreenLike(screen: NSScreen) -> Bool {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let menuBarConsumedHeight = frame.height - visible.height
        return menuBarConsumedHeight < 8
    }

    private func shouldRefreshExternal(force: Bool) -> Bool {
        if force {
            return true
        }
        return Date().timeIntervalSince(lastExternalRefreshAt) >= appActivationRefreshInterval
    }

    private func spacingMultiplier(compactMode: Bool, fullscreenLike: Bool) -> CGFloat {
        switch (compactMode, fullscreenLike) {
        case (true, true):
            return 0.648
        case (true, false):
            return 0.72
        case (false, true):
            return 0.72
        case (false, false):
            return 1
        }
    }
}
