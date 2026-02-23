import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

struct AXScannedItem {
    var item: ExternalMenuBarItem
    var element: AXUIElement
}

final class AXMenuBarScanner {
    private let menuBarThreshold: CGFloat = 42

    func scan(excludingBundleID: String, captureIcons: Bool = true) -> [AXScannedItem] {
        guard AXIsProcessTrusted() else {
            return []
        }

        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier > 0 &&
                !app.isTerminated &&
                app.bundleIdentifier != nil &&
                app.bundleIdentifier != excludingBundleID
        }

        var dedupe = Set<String>()
        var items: [AXScannedItem] = []
        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let menuBar = copyElementAttribute(on: appElement, name: kAXMenuBarAttribute as CFString),
                  let children = copyElementArrayAttribute(on: menuBar, name: kAXChildrenAttribute as CFString) else {
                continue
            }

            for (index, child) in children.enumerated() {
                guard let frame = frameForElement(child), isLikelyMenuBarItem(frame) else { continue }
                let title = inferredDisplayName(for: child, fallbackApp: app.localizedName ?? bundleID)
                let key = "\(app.processIdentifier)-\(Int(frame.minX.rounded()))-\(title)-\(index)"
                guard !dedupe.contains(key) else { continue }
                dedupe.insert(key)

                let model = ExternalMenuBarItem(
                    id: makeStableID(pid: app.processIdentifier, bundleID: bundleID, frame: frame, title: title, index: index),
                    ownerBundleID: bundleID,
                    title: title,
                    frameInScreen: frame,
                    supportsPressAction: supportsAction(kAXPressAction as String, for: child),
                    imageData: captureIcons ? captureIcon(in: frame) : nil
                )
                items.append(AXScannedItem(item: model, element: child))
            }
        }

        return items.sorted { $0.item.frameInScreen.minX > $1.item.frameInScreen.minX }
    }

    private func isLikelyMenuBarItem(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        for screen in NSScreen.screens {
            let nearTop = frame.maxY >= (screen.frame.maxY - menuBarThreshold)
            if nearTop && frame.midX > screen.frame.midX {
                return true
            }
        }
        return false
    }

    private func makeStableID(pid: pid_t, bundleID: String, frame: CGRect, title: String, index: Int) -> String {
        let payload = [String(pid), bundleID, String(Int(frame.minX.rounded())), String(Int(frame.width.rounded())), title, String(index)]
            .joined(separator: "|")
        var hash = UInt64(5381)
        for scalar in payload.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "ax-\(pid)-\(String(hash, radix: 16))"
    }

    private func inferredDisplayName(for element: AXUIElement, fallbackApp: String) -> String {
        let names: [CFString] = [kAXDescriptionAttribute as CFString, kAXTitleAttribute as CFString, kAXHelpAttribute as CFString]
        for name in names {
            if let value = copyStringAttribute(on: element, name: name), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return fallbackApp
    }

    private func captureIcon(in frame: CGRect) -> Data? {
        let width = max(16, min(32, frame.width))
        let height = max(16, min(24, frame.height))
        let rect = CGRect(x: frame.midX - (width / 2), y: frame.midY - (height / 2), width: width, height: height)
        guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution]) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private func supportsAction(_ action: String, for element: AXUIElement) -> Bool {
        var actionsValue: CFArray?
        let status = AXUIElementCopyActionNames(element, &actionsValue)
        guard status == .success, let actionsValue else { return false }
        let actions = actionsValue as NSArray
        return actions.compactMap { $0 as? String }.contains(action)
    }

    private func copyElementAttribute(on element: AXUIElement, name: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArrayAttribute(on element: AXUIElement, name: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(on element: AXUIElement, name: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private func frameForElement(_ element: AXUIElement) -> CGRect? {
        guard let position = copyPointAttribute(on: element, name: kAXPositionAttribute as CFString),
              let size = copySizeAttribute(on: element, name: kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func copyPointAttribute(on element: AXUIElement, name: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeBitCast(value, to: AXValue.self)
        var point = CGPoint.zero
        guard AXValueGetType(ax) == .cgPoint else { return nil }
        return AXValueGetValue(ax, .cgPoint, &point) ? point : nil
    }

    private func copySizeAttribute(on element: AXUIElement, name: CFString) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeBitCast(value, to: AXValue.self)
        var size = CGSize.zero
        guard AXValueGetType(ax) == .cgSize else { return nil }
        return AXValueGetValue(ax, .cgSize, &size) ? size : nil
    }
}
