import AppKit
import Foundation

final class NotchGeometryCalculator: NotchGeometryCalculating {
    private let topMargin: CGFloat

    init(topMargin: CGFloat = 6) {
        self.topMargin = topMargin
    }

    func layoutSnapshot(screen: NSScreen) -> NotchLayoutSnapshot {
        let frame = screen.frame
        let safe = screen.safeAreaInsets
        let notchWidth = max(0, frame.width - safe.left - safe.right)
        let hasNotch = notchWidth > 1
        let triggerWidth = hasNotch
            ? Self.clamp(notchWidth + 24, min: 170, max: 250)
            : 210
        let triggerHeight: CGFloat = 28
        let triggerFrame = CGRect(
            x: frame.midX - (triggerWidth / 2),
            y: frame.maxY - triggerHeight,
            width: triggerWidth,
            height: triggerHeight
        )
        let triggerOuterFrame = triggerFrame.insetBy(dx: -8, dy: -8)
        return NotchLayoutSnapshot(
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            triggerFrame: triggerFrame,
            triggerOuterFrame: triggerOuterFrame
        )
    }

    func panelFrame(screen: NSScreen, panelSize: CGSize) -> CGRect {
        let x = screen.frame.midX - (panelSize.width / 2)
        let y = screen.frame.maxY - panelSize.height - topMargin
        return CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(value, upper))
    }
}
