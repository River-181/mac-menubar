import SwiftUI

struct NotchPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topBar

            if viewModel.isPanelExpanded {
                Divider()
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundStyle)
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(preferredColorScheme)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.isPanelExpanded)
        .onHover { isHovering in
            viewModel.setPanelExpanded(isHovering)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.mediaState.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(mediaSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            mediaControls

            Text("\(viewModel.batteryPercentage)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExternalIconStripView(viewModel: viewModel)

            HStack(spacing: 8) {
                statBadge(title: "Battery", value: "\(viewModel.batteryPercentage)%")
                if viewModel.showSystemStats {
                    statBadge(title: "CPU", value: String(format: "%.1f%%", viewModel.cpuUsage))
                    statBadge(title: "RAM", value: String(format: "%.1f%%", viewModel.memoryUsage))
                }
            }

            Text("\(viewModel.mediaState.isPlaying ? "Playing" : "Paused") · \(viewModel.mediaState.sourceApp.isEmpty ? "Media" : viewModel.mediaState.sourceApp)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isNotchDropZoneEnabled {
                Text("Notch Drop Zone enabled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(PanelIconButtonStyle())

            Button {
                viewModel.playPause()
            } label: {
                Image(systemName: viewModel.mediaState.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PanelIconButtonStyle())

            Button {
                viewModel.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(PanelIconButtonStyle())
        }
        .font(.caption)
    }

    private func statBadge(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.primary.opacity(0.09), in: Capsule())
    }

    private var mediaSubtitle: String {
        if viewModel.mediaState.artist.isEmpty {
            return viewModel.mediaState.sourceApp.isEmpty ? "No active player" : viewModel.mediaState.sourceApp
        }
        if viewModel.mediaState.sourceApp.isEmpty {
            return viewModel.mediaState.artist
        }
        return "\(viewModel.mediaState.artist) - \(viewModel.mediaState.sourceApp)"
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if viewModel.useAccentTheme {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.24),
                    Color.black.opacity(0.56)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.black.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch viewModel.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 22, height: 22)
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.82 : 0.98))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.20 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
