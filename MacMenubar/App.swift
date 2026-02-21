import SwiftUI
import AppKit

@main
struct MacMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = MenuBarViewModel()
    private var statusBarController: StatusBarController?
    private var notchManager: NotchManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        notchManager = NotchManager(viewModel: viewModel)
        notchManager?.startMonitoring()
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu Bar Layout")
                .font(.headline)
            Toggle("Enable Dynamic Island Panel", isOn: $viewModel.isPanelEnabled)
            Toggle("Show CPU + Memory", isOn: $viewModel.showSystemStats)
            Toggle("Use Accent Theme", isOn: $viewModel.useAccentTheme)
        }
        .padding()
        .frame(width: 360)
    }
}
