import SwiftUI

struct IconStripView: View {
    let icons: [DockIcon]
    let state: OverlayState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(icons) { icon in
                    iconBubble(icon)
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollDisabled(icons.count <= maxVisibleWithoutScroll)
        .frame(height: state == .peek ? 40 : 44)
    }

    private var maxVisibleWithoutScroll: Int {
        switch state {
        case .hidden:
            0
        case .armed:
            3
        case .peek:
            6
        case .expand, .processing:
            10
        }
    }

    private func iconBubble(_ icon: DockIcon) -> some View {
        Image(systemName: icon.symbolName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.14))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .help(icon.title)
    }
}
