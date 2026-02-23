import AppKit
import Foundation

final class NotchGeometryCalculator: NotchGeometryCalculating {
    private let topMarginWithNotch: CGFloat
    private let topMarginWithoutNotch: CGFloat
    private let triggerWidth: CGFloat

    init(
        topMarginWithNotch: CGFloat = 6,
        topMarginWithoutNotch: CGFloat = 8,
        triggerWidth: CGFloat = 220
    ) {
        self.topMarginWithNotch = topMarginWithNotch
        self.topMarginWithoutNotch = topMarginWithoutNotch
        self.triggerWidth = triggerWidth
    }

    func capsuleFrame(screen: NSScreen, state: DockOverlayState, policy: NotchDefaultPolicy) -> CGRect {
        capsuleFrame(screen: screen, visualState: state, policy: policy, compactOverride: nil)
    }

    func capsuleFrame(
        screen: NSScreen,
        visualState: DockOverlayState,
        policy: NotchDefaultPolicy,
        compactOverride: Bool?
    ) -> CGRect {
        let frame = screen.frame
        let snapshot = layoutSnapshot(screen: screen, policy: policy)
        let panelSize = visualState.panelFrameSize
        let useCompact: Bool
        if let compactOverride {
            useCompact = compactOverride
        } else {
            useCompact = snapshot.compactMode
        }
        let topMargin = useCompact ? topMarginWithNotch : topMarginWithoutNotch
        let x = frame.midX - (panelSize.width / 2)
        let y = frame.maxY - panelSize.height - topMargin
        return CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    func triggerZone(screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let snapshot = layoutSnapshot(screen: screen, policy: .adaptiveAuto)
        let effectiveWidth = snapshot.hasNotch ? max(triggerWidth, 260) : triggerWidth
        let effectiveHeight: CGFloat = snapshot.hasNotch ? 32 : 22
        return CGRect(
            x: frame.midX - (effectiveWidth / 2),
            y: frame.maxY - effectiveHeight,
            width: effectiveWidth,
            height: effectiveHeight
        )
    }

    func hitMaskRect(for state: DockOverlayState, panelFrame: CGRect) -> CGRect {
        let snapshot: NotchLayoutSnapshot
        if let screen = screenContaining(point: CGPoint(x: panelFrame.midX, y: panelFrame.midY)) {
            snapshot = layoutSnapshot(screen: screen, policy: .adaptiveAuto)
        } else {
            snapshot = NotchLayoutSnapshot(
                screenWidth: panelFrame.width,
                safeLeft: 0,
                safeRight: 0,
                hasNotch: false,
                compactMode: false,
                spacing: 8
            )
        }
        let expansion = Self.hitMaskExpansion(for: state, snapshot: snapshot)
        let visualSize = state.capsuleSize
        let topInset: CGFloat = 8
        return CGRect(
            x: panelFrame.midX - (visualSize.width / 2),
            y: panelFrame.maxY - topInset - visualSize.height,
            width: visualSize.width,
            height: visualSize.height
        ).insetBy(dx: -expansion.horizontal, dy: -expansion.vertical)
    }

    func layoutSnapshot(screen: NSScreen, policy: NotchDefaultPolicy) -> NotchLayoutSnapshot {
        let frame = screen.frame
        let safe = screen.safeAreaInsets
        let fullscreenLike = (frame.height - screen.visibleFrame.height) < 8
        return Self.calculateLayout(
            screenWidth: frame.width,
            safeLeft: safe.left,
            safeRight: safe.right,
            policy: policy,
            fullscreenLike: fullscreenLike
        )
    }

    static func calculateLayout(
        screenWidth: CGFloat,
        safeLeft: CGFloat,
        safeRight: CGFloat,
        policy: NotchDefaultPolicy,
        fullscreenLike: Bool
    ) -> NotchLayoutSnapshot {
        let notchWidth = max(0, screenWidth - safeLeft - safeRight)
        let hasNotch = notchWidth > 0.1
        let compactMode: Bool
        switch policy {
        case .adaptiveAuto:
            compactMode = hasNotch
        case .alwaysCompact:
            compactMode = true
        case .alwaysRespect:
            compactMode = false
        }

        let baseSpacing = clamp((screenWidth / 180), min: 6, max: 14)
        let compactMultiplier: CGFloat = compactMode ? 0.72 : 1
        let fullscreenMultiplier: CGFloat = fullscreenLike ? 0.9 : 1
        let spacing = clamp(baseSpacing * compactMultiplier * fullscreenMultiplier, min: compactMode ? 3.5 : 6, max: compactMode ? 9.5 : 14)

        return NotchLayoutSnapshot(
            screenWidth: screenWidth,
            safeLeft: safeLeft,
            safeRight: safeRight,
            hasNotch: hasNotch,
            compactMode: compactMode,
            spacing: spacing
        )
    }

    static func hitMaskExpansion(for state: DockOverlayState, snapshot: NotchLayoutSnapshot) -> (horizontal: CGFloat, vertical: CGFloat) {
        let notchWidth = max(0, snapshot.screenWidth - snapshot.safeLeft - snapshot.safeRight)
        let baseHorizontal: CGFloat
        if !snapshot.hasNotch {
            baseHorizontal = 6
        } else if notchWidth < 180 {
            baseHorizontal = 7
        } else if notchWidth < 240 {
            baseHorizontal = 8
        } else {
            baseHorizontal = 9
        }

        let stateAdjustment: CGFloat
        switch state {
        case .idle, .peek:
            stateAdjustment = 1
        case .expand, .grab, .focus:
            stateAdjustment = -2
        case .workspace:
            stateAdjustment = -1.5
        }

        let horizontal = max(4, baseHorizontal + stateAdjustment)
        let vertical = max(4, (baseHorizontal * 0.9) + stateAdjustment)
        return (horizontal, vertical)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}
