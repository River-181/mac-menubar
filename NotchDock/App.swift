import SwiftUI

@main
struct NotchDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: NotchDockViewModel.shared)
        }
    }
}
