import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: NotchDockViewModel

    var body: some View {
        Form {
            Section("Trigger") {
                Text("The overlay opens only when pointer enters the strict notch trigger zone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Enter 35ms · Exit 100ms · Collapse grace 450ms")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Visible Icons") {
                HStack {
                    Text("Now showing")
                    Spacer()
                    Text("\(viewModel.visibleIcons.count) visible · \(viewModel.overflowIcons.count) overflow")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)

                ForEach(viewModel.candidateIcons) { icon in
                    HStack {
                        Label(icon.title, systemImage: icon.symbolName)
                        Spacer()
                        Text(icon.bucket == .pinned ? "Pinned" : "Shelf")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(
                            icon.title,
                            isOn: Binding(
                                get: { viewModel.selectedIconIDs.contains(icon.id) },
                                set: { viewModel.setIconEnabled(icon.id, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                    }
                }
            }

            Section("Keyboard Shortcut") {
                KeyboardShortcuts.Recorder("Toggle Overlay", name: .toggleExpand)
            }

            Section("Launch") {
                Toggle("Launch at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                ))
            }

            Section("About") {
                Text("NotchDock v1 hard reset focuses on stable drag hub and compact icon dock.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await viewModel.refreshIcons()
        }
    }
}
