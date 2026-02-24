import ApplicationServices
import CoreGraphics
import Foundation

final class AXActionBridge {
    func performPrimaryAction(on element: AXUIElement, fallbackFrame: CGRect?) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        guard let fallbackFrame else {
            return false
        }
        return performFallbackClick(frame: fallbackFrame)
    }

    func performFallbackClick(frame: CGRect) -> Bool {
        postSyntheticClick(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func postSyntheticClick(at point: CGPoint) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        source.localEventsSuppressionInterval = 0
        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
