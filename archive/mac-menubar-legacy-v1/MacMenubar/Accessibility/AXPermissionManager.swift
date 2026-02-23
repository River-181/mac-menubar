import ApplicationServices
import AppKit
import Foundation

final class AXPermissionManager: AXPermissionProviding {
    func currentState() -> MirrorAuthState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func requestPermission() -> MirrorAuthState {
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted ? .granted : .denied
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
