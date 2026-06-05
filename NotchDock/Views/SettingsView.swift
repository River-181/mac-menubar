import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: NotchDockViewModel

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            // MARK: Launch
            Section("Launch") {
                LaunchAtLogin.Toggle("Launch at Login")
            }

            // MARK: Keyboard Shortcuts
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder("Toggle hub", name: .toggleExpand)
                KeyboardShortcuts.Recorder("Undo last action", name: .undoLastAction)
            }

            // MARK: Performance
            Section("Performance") {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.perfSummaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Counters") {
                        viewModel.resetPerfSnapshot()
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
            }

            // MARK: Accessibility
            Section("Accessibility") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Global shortcuts need Accessibility permission.")
                            .font(.footnote)
                        Text("If hotkeys aren't responding, grant access in System Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(
                        "Enable\u{2026}",
                        destination: URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!
                    )
                    .font(.footnote)
                }
            }

            // MARK: About
            Section("About") {
                HStack(alignment: .top, spacing: 12) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .cornerRadius(10)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NotchDock")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("A refined notch-native action hub for macOS.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("View on GitHub", destination: URL(string: "https://github.com/River-181/mac-menubar")!)
                            .font(.footnote)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460)
    }
}
