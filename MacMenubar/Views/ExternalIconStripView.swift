import AppKit
import SwiftUI

struct ExternalIconStripView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if viewModel.externalVisibleItems.isEmpty {
                    Text(viewModel.mirrorAuthState == .granted ? "No mirrored icons" : "Accessibility required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.externalVisibleItems) { item in
                        Button {
                            viewModel.performExternalItemPrimaryAction(itemID: item.id)
                        } label: {
                            iconContent(for: item)
                        }
                        .buttonStyle(ExternalStripButtonStyle())
                        .help(item.displayName)
                    }
                }

                if !viewModel.externalOverflowItems.isEmpty {
                    Text("+\(viewModel.externalOverflowItems.count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.12), in: Capsule())
                        .help("External overflow")
                }
            }
            Text(viewModel.externalStatusSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func iconContent(for item: ExternalMenuBarItem) -> some View {
        if let data = item.iconPNGData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .padding(6)
                .background(.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Text(String(item.displayName.prefix(1)).uppercased())
                .font(.caption2.weight(.semibold))
                .frame(width: 20, height: 20)
                .padding(4)
                .background(.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ExternalStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.84 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
