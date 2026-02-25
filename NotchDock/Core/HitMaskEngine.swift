import AppKit
import Foundation

final class HitMaskEngine {
    func capsuleMaskFrame(panelFrame: CGRect, state: OverlayState, hasNotch: Bool, notchWidth: CGFloat) -> CGRect {
        let size = state.capsuleSize
        guard size.width > 0, size.height > 0 else { return .zero }
        let frame = CGRect(
            x: panelFrame.midX - (size.width / 2),
            y: panelFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )
        let notchBias: CGFloat = 8
        return frame.insetBy(dx: -notchBias, dy: -(notchBias - 1))
    }

    func isInsideCapsule(point: CGPoint, panelFrame: CGRect, state: OverlayState, hasNotch: Bool, notchWidth: CGFloat) -> Bool {
        let rect = capsuleMaskFrame(
            panelFrame: panelFrame,
            state: state,
            hasNotch: hasNotch,
            notchWidth: notchWidth
        )
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return false }

        let radius = rect.height / 2
        let centerBand = CGRect(
            x: rect.minX + radius,
            y: rect.minY,
            width: max(0, rect.width - (radius * 2)),
            height: rect.height
        )
        if centerBand.contains(point) {
            return true
        }

        let leftCenter = CGPoint(x: rect.minX + radius, y: rect.midY)
        let rightCenter = CGPoint(x: rect.maxX - radius, y: rect.midY)
        return hypot(point.x - leftCenter.x, point.y - leftCenter.y) <= radius
            || hypot(point.x - rightCenter.x, point.y - rightCenter.y) <= radius
    }
}
