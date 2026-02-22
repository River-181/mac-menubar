import ApplicationServices
import CoreGraphics
import Foundation

final class AXActionBridge: AXActionBridging {
    func performPrimaryAction(on element: AXUIElement, fallbackFrame: CGRect?) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }

        guard let fallbackFrame else {
            return false
        }
        return postSyntheticClick(at: CGPoint(x: fallbackFrame.midX, y: fallbackFrame.midY))
    }

    func setHidden(_ hidden: Bool, for element: AXUIElement) -> ExternalHideFailureReason? {
        guard AXIsProcessTrusted() else {
            return .permissionDenied
        }

        let hiddenKey = kAXHiddenAttribute as CFString
        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(element, hiddenKey, &settable)

        guard settableStatus == .success, settable.boolValue else {
            return .unsupportedAttribute
        }

        let value: CFTypeRef = hidden ? kCFBooleanTrue : kCFBooleanFalse
        let status = AXUIElementSetAttributeValue(element, hiddenKey, value)
        guard status == .success else {
            return .actionFailed
        }

        return nil
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
