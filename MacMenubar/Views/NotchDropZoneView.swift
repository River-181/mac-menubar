import SwiftUI

struct NotchDropZoneView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionFrames: [NotchActionKind: CGRect] = [:]

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
        .coordinateSpace(name: "drop-zone")
        .animation(expansionAnimation, value: isExpanded)
        .onHover { hovering in
            viewModel.setDropZoneHover(hovering)
        }
        .background(dropTrackingOverlay)
        .onPreferenceChange(ActionFramePreferenceKey.self) { actionFrames = $0 }
    }

    private var dropTrackingOverlay: some View {
        DropTrackingView(
            onDragEntered: { urls in
                viewModel.setDropZoneHover(true)
                viewModel.beginDragSession(with: urls)
            },
            onDragUpdated: { point in
                viewModel.updateDragTarget(action(at: point))
            },
            onDragExited: {
                viewModel.setDropZoneHover(false)
                viewModel.endDragSession()
            },
            onPerformDrop: { urls, point in
                let targeted = action(at: point)
                viewModel.handleDroppedItems(urls, preferredAction: targeted)
            }
        )
        .allowsHitTesting(true)
        .opacity(0.01)
    }

    private var isExpanded: Bool {
        viewModel.isDropZoneHovered || viewModel.dragSession.isFileDrag || viewModel.notchDropState != .idle
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: actionColumns, spacing: 8) {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var helpText: String {
        if case .processing = viewModel.notchDropState {
            return "Processing files..."
        }
        if let action = viewModel.targetedDropAction {
            return "Drop to run \(action.displayName)."
        }
        if let action = viewModel.recommendedDropAction, viewModel.dragSession.isFileDrag {
            return "Recommended: \(action.displayName)."
        }
        return "Hover and drop files here: optimize, convert, compress, collect, or trash."
    }

    @ViewBuilder
    private func actionChip(_ action: NotchActionKind) -> some View {
        let isAvailable = viewModel.availableDropActions.contains(action)
        let isProcessing = viewModel.notchDropState == .processing
        let isTargeted = viewModel.targetedDropAction == action
        let isRecommended = viewModel.recommendedDropAction == action && viewModel.targetedDropAction == nil && viewModel.dragSession.isFileDrag

        Button {
            viewModel.performNotchAction(action, files: viewModel.droppedFiles)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.symbolName)
                    .font(.caption.weight(.semibold))
                Text(shortLabel(for: action))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isAvailable ? .primary : .secondary)
        .opacity(isAvailable ? 1 : 0.45)
        .background(chipBackground(isAvailable: isAvailable, isTargeted: isTargeted, isRecommended: isRecommended))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor.opacity(0.95) : .clear, lineWidth: 1.4)
        )
        .disabled(!isAvailable || isProcessing)
        .help(action.displayName)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: ActionFramePreferenceKey.self,
                        value: [action: proxy.frame(in: .named("drop-zone"))]
                    )
            }
        )
    }

    @ViewBuilder
    private func chipBackground(isAvailable: Bool, isTargeted: Bool, isRecommended: Bool) -> some View {
        let baseOpacity: CGFloat = isAvailable ? 0.09 : 0.04
        let highlightOpacity: CGFloat = isTargeted ? 0.18 : (isRecommended ? 0.12 : baseOpacity)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.primary.opacity(highlightOpacity))
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.14), value: isTargeted)
    }

    private func shortLabel(for action: NotchActionKind) -> String {
        switch action {
        case .imageToPDF: return "Img→PDF"
        case .pdfToImages: return "PDF→Img"
        case .compressZip: return "Zip"
        case .extractZip: return "Unzip"
        case .optimizeImages: return "Opt Img"
        case .optimizePDFKeepText: return "Opt PDF"
        case .resizeImages: return "Resize"
        case .sendToWorkbench: return "Desk"
        case .moveToTrash: return "Trash"
        }
    }

    private func action(at point: CGPoint) -> NotchActionKind? {
        actionFrames.first { pair in
            pair.value.contains(point) && viewModel.availableDropActions.contains(pair.key)
        }?.key
    }

    private var actionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 56, maximum: 72), spacing: 8), count: 5)
    }

    private var expansionAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .interactiveSpring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.10)
    }
}

private struct ActionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [NotchActionKind: CGRect] = [:]

    static func reduce(value: inout [NotchActionKind: CGRect], nextValue: () -> [NotchActionKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
