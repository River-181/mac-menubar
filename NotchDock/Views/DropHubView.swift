import SwiftUI
import UniformTypeIdentifiers

struct DropHubView: View {
    let actions: [WorkActionKind]
    let targetedAction: WorkActionKind?
    let onRunAction: (WorkActionKind) -> Void
    let onDrop: (WorkActionKind, [URL]) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(actions) { action in
                DropChip(
                    action: action,
                    highlighted: targetedAction == action,
                    onSelect: { onRunAction(action) },
                    onDrop: { urls in onDrop(action, urls) }
                )
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 10, alignment: .top)
        ]
    }
}

private struct DropChip: View {
    let action: WorkActionKind
    let highlighted: Bool
    let onSelect: () -> Void
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(highlighted || isTargeted ? 0.20 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(highlighted || isTargeted ? 0.34 : 0.18), lineWidth: 1)
            )
            .scaleEffect(highlighted || isTargeted ? 1.03 : 1)
            .shadow(color: .black.opacity(highlighted || isTargeted ? 0.18 : 0), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadURLs(providers: providers, onComplete: onDrop)
            return true
        }
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private func loadURLs(providers: [NSItemProvider], onComplete: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var output: URL?
                if let data = item as? Data {
                    output = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    output = url
                } else if let text = item as? String {
                    output = URL(string: text)
                }
                if let output {
                    lock.lock()
                    urls.append(output)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            onComplete(urls)
        }
    }
}
