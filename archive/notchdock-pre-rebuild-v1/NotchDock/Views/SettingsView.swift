import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct SettingsView: View {
    @ObservedObject var viewModel: NotchDockViewModel

    var body: some View {
        Form {
            Section("Menu Bar Compaction") {
                Picker("Default Policy", selection: Binding(
                    get: { viewModel.notchDefaultPolicy },
                    set: { viewModel.setPolicy($0) }
                )) {
                    ForEach(NotchDefaultPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Text("Effective spacing: \(viewModel.effectiveSpacing, specifier: "%.1f")pt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Work Hub Motion") {
                Toggle("Interactive magnet", isOn: Binding(
                    get: { viewModel.enableInteractiveMagnet },
                    set: { viewModel.setInteractiveMagnet($0) }
                ))

                Toggle("Enable workspace (experimental)", isOn: Binding(
                    get: { viewModel.enableWorkspace },
                    set: { viewModel.setWorkspaceEnabled($0) }
                ))

                Toggle("Reduce motion", isOn: Binding(
                    get: { viewModel.reduceMotionEnabled },
                    set: { viewModel.setReduceMotion($0) }
                ))
            }

            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder("Toggle Expand", name: .toggleExpand)
                KeyboardShortcuts.Recorder("Toggle Workspace", name: .toggleWorkspace)
                KeyboardShortcuts.Recorder("Next Group", name: .nextGroup)
                KeyboardShortcuts.Recorder("Previous Group", name: .previousGroup)
            }

            Section("App Runtime") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                ))
            }

            Section("External Icons") {
                HStack {
                    Text("Accessibility")
                    Spacer(minLength: 0)
                    Text(viewModel.externalAuthState.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show running app icons", isOn: Binding(
                    get: { viewModel.showRunningAppIcons },
                    set: { viewModel.setShowRunningAppIcons($0) }
                ))
                Button("Refresh icon sources") {
                    Task { @MainActor in
                        await viewModel.refreshIcons()
                    }
                    viewModel.refreshExternalIcons()
                }
            }

            Section("About") {
                Text("NotchDock focuses on tactile notch-linked overlay interactions, icon organization, and file actions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
