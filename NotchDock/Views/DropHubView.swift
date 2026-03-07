import SwiftUI
import UniformTypeIdentifiers

struct DropHubView: View {
    let actions: [WorkActionKind]
    let recommendedAction: WorkActionKind?
    let targetedAction: WorkActionKind?
    let onRunAction: (WorkActionKind) -> Void
    let onDrop: (WorkActionKind, [URL]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Drop actions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Drag onto a chip or click to pick files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(actions) { action in
                    DropChip(
                        action: action,
                        highlighted: targetedAction == action,
                        emphasized: recommendedAction == action,
                        onSelect: { onRunAction(action) },
                        onDrop: { urls in onDrop(action, urls) }
                    )
                }
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
    let emphasized: Bool
    let onSelect: () -> Void
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(iconBackground)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if emphasized {
                            Text("Best")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.72))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(emphasized ? "Recommended for current files" : "Click or drop to run")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(highlighted || isTargeted ? 1.035 : 1)
            .offset(y: highlighted || isTargeted ? -1 : 0)
            .shadow(color: .black.opacity(highlighted || isTargeted ? 0.18 : 0.08), radius: highlighted || isTargeted ? 12 : 6, x: 0, y: highlighted || isTargeted ? 8 : 3)
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadURLs(providers: providers, onComplete: onDrop)
            return true
        }
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: highlighted)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.84), value: isTargeted)
    }

    private var backgroundFill: Color {
        if highlighted || isTargeted {
            return .white.opacity(0.22)
        }
        if emphasized {
            return .white.opacity(0.14)
        }
        return .white.opacity(0.09)
    }

    private var borderColor: Color {
        if highlighted || isTargeted {
            return .white.opacity(0.38)
        }
        if emphasized {
            return .white.opacity(0.26)
        }
        return .white.opacity(0.16)
    }

    private var iconBackground: Color {
        if highlighted || isTargeted {
            return .white.opacity(0.22)
        }
        return .white.opacity(0.12)
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
