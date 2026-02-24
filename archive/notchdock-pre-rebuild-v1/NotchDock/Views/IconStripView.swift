import SwiftUI
import UniformTypeIdentifiers

struct IconStripView: View {
    let icons: [DockIcon]
    let state: DockOverlayState
    let spacing: CGFloat
    let onReorder: (String, String) -> Void
    let onUse: (String) -> Void
    let onFocus: (String) -> Void

    @State private var draggingID: String?

    var body: some View {
        Group {
            if shouldScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    iconRow
                        .padding(.horizontal, 2)
                }
                .clipped()
            } else {
                iconRow
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: state == .idle ? 30 : 34)
    }

    private var shouldScroll: Bool {
        icons.count > maxVisibleWithoutScroll
    }

    private var maxVisibleWithoutScroll: Int {
        switch state {
        case .idle:
            return 5
        case .peek:
            return 8
        case .expand, .grab, .focus, .workspace:
            return 12
        }
    }

    private var iconRow: some View {
        HStack(spacing: spacing) {
            ForEach(icons) { icon in
                iconButton(icon)
            }
        }
    }

    private func iconButton(_ icon: DockIcon) -> some View {
        Button {
            onUse(icon.id)
        } label: {
            iconGlyph(icon)
                .frame(width: state == .idle ? 28 : 30, height: state == .idle ? 28 : 30)
                .background(Circle().fill(.white.opacity(0.12)))
                .scaleEffect(draggingID == icon.id ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .help(icon.title)
        .onHover { inside in
            if inside && (state == .expand || state == .focus || state == .grab) {
                onFocus(icon.id)
            }
        }
        .onDrag {
            draggingID = icon.id
            return NSItemProvider(object: NSString(string: icon.id))
        }
        .onDrop(
            of: [UTType.text],
            delegate: IconReorderDropDelegate(
                targetID: icon.id,
                draggingID: $draggingID,
                onReorder: onReorder
            )
        )
    }

    @ViewBuilder
    private func iconGlyph(_ icon: DockIcon) -> some View {
        if let data = icon.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .padding(6)
        } else {
            Image(systemName: icon.symbolOrImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct IconReorderDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggingID: String?
    let onReorder: (String, String) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingID, draggingID != targetID else {
            self.draggingID = nil
            return false
        }
        onReorder(draggingID, targetID)
        self.draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        onReorder(draggingID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
