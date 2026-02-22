import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

struct AXScannedMenuBarItem {
    var item: ExternalMenuBarItem
    var element: AXUIElement
}

final class AXMenuBarScanner {
    private let menuBarThreshold: CGFloat = 42

    func scan(excludingBundleID: String) -> [AXScannedMenuBarItem] {
        guard AXIsProcessTrusted() else {
            return []
        }

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier > 0 &&
                app.bundleIdentifier != nil &&
                app.bundleIdentifier != excludingBundleID &&
                !app.isTerminated
            }

        var dedupe = Set<String>()
        var scanned: [AXScannedMenuBarItem] = []
        let now = Date()

        for app in runningApps {
            let bundleID = app.bundleIdentifier ?? "unknown"
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let menuBar = copyElementAttribute(on: appElement, name: kAXMenuBarAttribute as CFString) else {
                continue
            }
            guard let children = copyElementArrayAttribute(on: menuBar, name: kAXChildrenAttribute as CFString) else {
                continue
            }

            for (index, child) in children.enumerated() {
                guard let frame = frameForElement(child), isLikelyMenuBarItem(frame) else {
                    continue
                }

                let role = copyStringAttribute(on: child, name: kAXRoleAttribute as CFString)
                if let role, role != (kAXMenuBarItemRole as String), role != "AXButton" {
                    continue
                }

                let title = inferredDisplayName(for: child, fallbackApp: app.localizedName ?? bundleID)
                let dedupeKey = "\(app.processIdentifier)-\(Int(frame.origin.x.rounded()))-\(Int(frame.width.rounded()))-\(title)"
                guard !dedupe.contains(dedupeKey) else {
                    continue
                }
                dedupe.insert(dedupeKey)

                let supportsPressAction = supportsAction(kAXPressAction as String, for: child)
                let iconData = captureIcon(in: frame)
                let id = makeStableID(
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    frame: frame,
                    title: title,
                    index: index
                )

                let model = ExternalMenuBarItem(
                    id: id,
                    ownerBundleID: bundleID,
                    displayName: title,
                    frameInScreen: frame,
                    isVisibleInSystemBar: true,
                    supportsPressAction: supportsPressAction,
                    iconPNGData: iconData,
                    lastSeenAt: now,
                    lastInteractionAt: .distantPast,
                    shelfState: .none
                )
                scanned.append(AXScannedMenuBarItem(item: model, element: child))
            }
        }

        return scanned.sorted { lhs, rhs in
            lhs.item.frameInScreen.minX > rhs.item.frameInScreen.minX
        }
    }

    private func isLikelyMenuBarItem(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else {
            return false
        }

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let nearTop = frame.maxY >= (screenFrame.maxY - menuBarThreshold)
            let rightHalf = frame.midX > screenFrame.midX
            if nearTop && rightHalf {
                return true
            }
        }
        return false
    }

    private func makeStableID(pid: pid_t, bundleID: String, frame: CGRect, title: String, index: Int) -> String {
        let payload = [
            String(pid),
            bundleID,
            String(Int(frame.minX.rounded())),
            String(Int(frame.width.rounded())),
            title,
            String(index)
        ].joined(separator: "|")

        var hash = UInt64(5381)
        for scalar in payload.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "ext-\(pid)-\(String(hash, radix: 16))"
    }

    private func inferredDisplayName(for element: AXUIElement, fallbackApp: String) -> String {
        let candidates: [CFString] = [
            kAXDescriptionAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXHelpAttribute as CFString
        ]

        for candidate in candidates {
            if let value = copyStringAttribute(on: element, name: candidate), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallbackApp
    }

    private func captureIcon(in frame: CGRect) -> Data? {
        let width = max(16, min(32, frame.width))
        let height = max(16, min(24, frame.height))
        let captureRect = CGRect(
            x: frame.midX - (width / 2),
            y: frame.midY - (height / 2),
            width: width,
            height: height
        )

        guard let image = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private func supportsAction(_ action: String, for element: AXUIElement) -> Bool {
        var actionsValue: CFArray?
        let status = AXUIElementCopyActionNames(element, &actionsValue)
        guard status == .success, let actionsValue else {
            return false
        }

        let actions = actionsValue as NSArray
        return actions.compactMap { $0 as? String }.contains(action)
    }

    private func frameForElement(_ element: AXUIElement) -> CGRect? {
        guard
            let position = copyPointAttribute(on: element, name: kAXPositionAttribute as CFString),
            let size = copySizeAttribute(on: element, name: kAXSizeAttribute as CFString)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func copyElementAttribute(on element: AXUIElement, name: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArrayAttribute(on element: AXUIElement, name: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(on element: AXUIElement, name: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private func copyPointAttribute(on element: AXUIElement, name: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)

        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        if AXValueGetValue(axValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func copySizeAttribute(on element: AXUIElement, name: CFString) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)

        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        if AXValueGetValue(axValue, .cgSize, &size) {
            return size
        }
        return nil
    }
}
