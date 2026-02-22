import AppKit
import SwiftUI

@main
struct MacMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .frame(width: 660, height: 720)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = MenuBarViewModel()

    private var statusBarController: StatusBarController?
    private var notchManager: NotchManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
        notchManager = NotchManager(viewModel: viewModel)
        notchManager?.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchManager?.stopMonitoring()
        viewModel.shutdown()
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image("BrandLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("MacMenubar")
                    .font(.title3.weight(.semibold))
            }

            GroupBox("Panel") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Dynamic Island Panel", isOn: $viewModel.isPanelEnabled)
                    Toggle("Show CPU + Memory", isOn: $viewModel.showSystemStats)
                    Toggle("Use Accent Theme", isOn: $viewModel.useAccentTheme)
                    Picker("Theme", selection: $viewModel.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 6)
            }

            GroupBox("Menu Bar Compaction") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Default Policy", selection: Binding(
                        get: { viewModel.notchDefaultPolicy },
                        set: { viewModel.setNotchDefaultPolicy($0) }
                    )) {
                        ForEach(NotchDefaultPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Current mode: \(viewModel.notchDisplayMode.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Compact icon spacing", isOn: Binding(
                        get: { viewModel.compactMenuBarSpacingEnabled },
                        set: { viewModel.setCompactMenuBarSpacingEnabled($0) }
                    ))

                    Text("System-wide notch masking is OS-level. MacMenubar only adjusts its own compact policy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open BetterDisplay", destination: URL(string: "https://github.com/waydabber/BetterDisplay")!)
                        .font(.caption)
                }
                .padding(.top, 6)
            }

            GroupBox("Notch Actions") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Notch Drop Zone", isOn: $viewModel.isNotchDropZoneEnabled)
                    Toggle("Enable Instant Execution", isOn: $viewModel.instantExecutionEnabled)
                    Text("Undo timeout: 8s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.lastReclaimedBytes > 0 {
                        Text("Last reclaimed: \(ByteCountFormatter.string(fromByteCount: viewModel.lastReclaimedBytes, countStyle: .file))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Open Workbench Folder") {
                            viewModel.openWorkbenchFolder()
                        }
                        if !viewModel.notchActionMessage.isEmpty {
                            Text(viewModel.notchActionMessage)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(viewModel.notchActionIsError ? .orange : .secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Work Hub Motion") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Motion style")
                        Text("Apple subtle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.1), in: Capsule())
                    }

                    Picker("Hub style", selection: Binding(
                        get: { viewModel.workHubStyle },
                        set: { viewModel.setWorkHubStyle($0) }
                    )) {
                        ForEach(WorkHubStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Interactive magnet", isOn: Binding(
                        get: { viewModel.interactiveMagnetEnabled },
                        set: { viewModel.setInteractiveMagnetEnabled($0) }
                    ))

                    HStack(spacing: 8) {
                        Text("Reduce Motion detected")
                            .font(.caption)
                        Text(reduceMotion ? "On" : "Off")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(reduceMotion ? .orange : .secondary)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("External Icons") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Accessibility")
                        Text(authStateLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(authStateColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(authStateColor)
                    }

                    if viewModel.mirrorAuthState == .granted {
                        Text(viewModel.externalStatusSummary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(viewModel.externalHideStatsSummary)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("Hidden Shelf \(viewModel.externalHiddenShelfItems.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Request Permission") {
                            viewModel.requestAXPermission()
                        }

                        Button("Open Accessibility Settings") {
                            viewModel.openAXSettings()
                        }

                        Button("Refresh") {
                            viewModel.refreshExternalItems()
                        }
                        .disabled(viewModel.mirrorAuthState != .granted)
                    }

                    if !viewModel.externalLastOperationMessage.isEmpty {
                        HStack(spacing: 8) {
                            Text(viewModel.externalLastOperationMessage)
                                .font(.caption)
                                .foregroundStyle(viewModel.externalLastOperationIsWarning ? .orange : .green)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Button("Clear") {
                                viewModel.clearExternalStatusMessage()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                        }
                    }

                    if listedExternalItems.isEmpty {
                        Text(viewModel.mirrorAuthState == .granted ? "No external menu icons detected." : "Grant Accessibility to mirror external icons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(listedExternalItems) { item in
                                    ExternalIconPreferenceRow(viewModel: viewModel, item: item)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 180)
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Icon Visibility Policy") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.icons.sorted(by: { $0.priority > $1.priority })) { icon in
                        HStack {
                            Text(icon.title)
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { icon.group },
                                set: { viewModel.setIconGroup(id: icon.id, group: $0) }
                            )) {
                                ForEach(VisibilityGroup.allCases) { group in
                                    Text(group.displayName).tag(group)
                                }
                            }
                            .pickerStyle(.menu)
                            Spacer(minLength: 8)
                            Text(icon.isVisible ? "Visible" : "Hidden")
                                .foregroundStyle(icon.isVisible ? Color.green : Color.secondary)
                                .font(.caption)
                        }
                    }
                }
                .padding(.top, 6)
            }

            GroupBox("Current Layout") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screen: \(Int(viewModel.layoutSnapshot.screenWidth))")
                    Text("Notch Width: \(Int(viewModel.layoutSnapshot.notchWidth))")
                    Text("Reserved Center: \(Int(viewModel.layoutSnapshot.reservedCenterWidth))")
                    Text("Side Budget: \(Int(viewModel.layoutSnapshot.sideBudget))")
                    Text("Spacing: \(String(format: "%.1f", viewModel.layoutSnapshot.spacing))")
                    Text("Compact Mode: \(viewModel.layoutSnapshot.effectiveCompactMode ? "On" : "Off")")
                    Text("Spacing Multiplier: \(String(format: "%.3f", viewModel.layoutSnapshot.effectiveSpacingMultiplier))")
                    Text("External Visible: \(viewModel.externalVisibleItems.count)")
                    Text("External Overflow: \(viewModel.externalOverflowItems.count)")
                    Text("External Hidden Shelf: \(viewModel.externalHiddenShelfItems.count)")
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.top, 6)
            }

            Spacer()
        }
        .padding(20)
    }

    private var authStateLabel: String {
        switch viewModel.mirrorAuthState {
        case .unknown:
            return "Unknown"
        case .denied:
            return "Denied"
        case .granted:
            return "Granted"
        }
    }

    private var authStateColor: Color {
        switch viewModel.mirrorAuthState {
        case .unknown:
            return .secondary
        case .denied:
            return .red
        case .granted:
            return .green
        }
    }

    private var listedExternalItems: [ExternalMenuBarItem] {
        var items = viewModel.externalItems
        let existingIDs = Set(items.map(\.id))
        items.append(contentsOf: viewModel.externalHiddenShelfItems.filter { !existingIDs.contains($0.id) })
        return items.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

private struct ExternalIconPreferenceRow: View {
    @ObservedObject var viewModel: MenuBarViewModel
    let item: ExternalMenuBarItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(item.ownerBundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)

            Toggle("Pin", isOn: Binding(
                get: { viewModel.isExternalPinned(itemID: item.id) },
                set: { viewModel.setExternalItemPinned(itemID: item.id, pinned: $0) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 55)

            Picker("", selection: Binding(
                get: { viewModel.externalMode(for: item.id) },
                set: { viewModel.setExternalItemMode(itemID: item.id, mode: $0) }
            )) {
                ForEach(ExternalItemVisibilityMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.shelfState == .staleHidden {
            Text("Stale Hidden")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            switch viewModel.resolvedExternalState(for: item.id) {
            case .hiddenApplied:
                Text("Hidden Applied")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .mirrorOnly:
                Text("Mirror Only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .downgraded(let reason):
                Text("Downgraded: \(reason.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }
}
