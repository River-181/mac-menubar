import SwiftUI
import UniformTypeIdentifiers

struct NotchDropZoneView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(.primary.opacity(0.26))
                .frame(width: isExpanded ? 64 : 44, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isExpanded ? 10 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isExpanded)
        .onHover { hovering in
            viewModel.setDropZoneHover(hovering)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    private var isExpanded: Bool {
        viewModel.isDropZoneHovered || isDropTargeted || viewModel.notchDropState != .idle
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(NotchActionKind.allCases) { action in
                    actionChip(action)
                }
            }

            if !viewModel.notchActionMessage.isEmpty {
                HStack(spacing: 8) {
                    Text(viewModel.notchActionMessage)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(viewModel.notchActionIsError ? .orange : .secondary)
                    Spacer(minLength: 6)
                    if viewModel.canUndoLastDangerousAction {
                        Button("Undo") {
                            viewModel.undoLastDangerousAction()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                    }
                }
            } else {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var helpText: String {
        if isDropTargeted {
            return "Drop files to run the recommended action instantly."
        }
        if viewModel.notchDropState == .processing {
            return "Processing files..."
        }
        return "Hover and drop files here: convert, compress, workbench, or trash."
    }

    @ViewBuilder
    private func actionChip(_ action: NotchActionKind) -> some View {
        let isAvailable = viewModel.availableDropActions.contains(action)
        let isProcessing = viewModel.notchDropState == .processing

        Button {
            viewModel.performNotchAction(action, files: viewModel.droppedFiles)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.symbolName)
                    .font(.caption.weight(.semibold))
                Text(shortLabel(for: action))
                    .font(.caption2)
            }
            .frame(width: 56, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAvailable ? .primary : .secondary)
        .opacity(isAvailable ? 1 : 0.45)
        .background(.primary.opacity(isAvailable ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(!isAvailable || isProcessing)
        .help(action.displayName)
    }

    private func shortLabel(for action: NotchActionKind) -> String {
        switch action {
        case .imageToPDF: return "Img→PDF"
        case .pdfToImages: return "PDF→Img"
        case .compressZip: return "Zip"
        case .sendToWorkbench: return "Desk"
        case .moveToTrash: return "Trash"
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        loadFileURLs(from: providers) { urls in
            viewModel.handleDroppedItems(urls)
        }
        return true
    }

    private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                var resolved: URL?
                if let url = item as? URL {
                    resolved = url
                } else if let data = item as? Data {
                    resolved = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
                } else if let string = item as? String {
                    resolved = URL(string: string)
                }

                guard let resolved else { return }
                collector.append(resolved)
            }
        }

        group.notify(queue: .main) {
            completion(Array(Set(collector.values)).sorted(by: { $0.path < $1.path }))
        }
    }
}

private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        values.append(url)
        lock.unlock()
    }
}
