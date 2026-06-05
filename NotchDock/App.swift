import SwiftUI

@main
struct NotchDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings window is owned entirely by AppDelegate (NSWindow).
        // An empty Settings scene satisfies the App protocol without creating
        // a competing SwiftUI-managed window.
        Settings {
            EmptyView()
        }
        .commands {
            // Settings is opened from the status-bar menu via AppDelegate, so
            // suppress the default ⌘, menu item to avoid opening the empty scene.
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
