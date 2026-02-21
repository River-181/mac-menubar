import SwiftUI

struct NotchPanelView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Now Playing", systemImage: "music.note")
                Spacer()
                Text("Battery \(viewModel.batteryPercentage)%")
            }
            if isHovered {
                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.showSystemStats {
                        Text(String(format: "CPU %.1f%% · RAM %.1f%%", viewModel.cpuUsage, viewModel.memoryUsage))
                            .font(.caption)
                    }
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.todayEvents, id: \.self) { event in
                        Text("• \(event)").font(.caption)
                    }
                    ForEach(viewModel.todos) { todo in
                        Text(todo.isDone ? "✅ \(todo.title)" : "⬜️ \(todo.title)")
                            .font(.caption)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundStyle)
        .cornerRadius(16)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isHovered)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if viewModel.useAccentTheme {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [.accentColor.opacity(0.55), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }
}
