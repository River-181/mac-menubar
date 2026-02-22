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
            onDragUpdated: { point, dynamics in
                viewModel.updateDragDynamics(dynamics)
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
        viewModel.isDropZoneHovered
            || viewModel.dragSession.isFileDrag
            || viewModel.notchDropState != .idle
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
                .transition(messageTransition)
                .animation(messageAnimation, value: viewModel.notchActionMessage)
            } else {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var helpText: String {
        switch viewModel.notchDropState {
        case .preheat:
            return "Preparing actions..."
        case .processing:
            return "Processing files..."
        case .dropCommit(let action):
            return "Applying \(action.displayName)..."
        default:
            break
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
        let neighborOffset = neighborOffset(for: action)
        let targetLift = isTargeted ? (-2 * viewModel.magnetSnapStrength) : 0
        let targetScale = isTargeted ? (1 + (0.06 * viewModel.magnetSnapStrength)) : 1
        let shadowOpacity = isTargeted ? 0.28 : 0.08
        let shadowRadius: CGFloat = isTargeted ? 9 : 2

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
                .strokeBorder(isTargeted ? Color.primary.opacity(0.45) : .clear, lineWidth: 1.2)
        )
        .scaleEffect(targetScale)
        .offset(x: neighborOffset, y: targetLift)
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: isTargeted ? 3 : 1)
        .animation(chipSnapAnimation, value: viewModel.targetedDropAction)
        .animation(chipSnapAnimation, value: viewModel.magnetSnapStrength)
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
        let highlightOpacity: CGFloat = isTargeted ? 0.20 : (isRecommended ? 0.13 : baseOpacity)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.primary.opacity(highlightOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(isTargeted ? 0.06 : 0))
            )
            .animation(chipFocusReleaseAnimation, value: isTargeted)
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
        return .interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.10)
    }

    private var chipSnapAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .spring(response: 0.22, dampingFraction: 0.80, blendDuration: 0.08)
    }

    private var chipFocusReleaseAnimation: Animation {
        .easeOut(duration: 0.14)
    }

    private var messageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity.animation(.easeOut(duration: 0.22))),
            removal: .move(edge: .top).combined(with: .opacity.animation(.easeOut(duration: 0.18)))
        )
    }

    private var messageAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .easeOut(duration: 0.22)
    }

    private func neighborOffset(for action: NotchActionKind) -> CGFloat {
        guard viewModel.interactiveMagnetEnabled else { return 0 }
        guard let target = viewModel.targetedDropAction else { return 0 }
        guard action != target else { return 0 }

        guard
            let sourceIndex = NotchActionKind.allCases.firstIndex(of: action),
            let targetIndex = NotchActionKind.allCases.firstIndex(of: target)
        else {
            return 0
        }

        let distance = abs(sourceIndex - targetIndex)
        guard distance <= 2 else { return 0 }

        let direction: CGFloat = sourceIndex < targetIndex ? 1 : -1
        let baseOffset: CGFloat
        switch distance {
        case 1:
            baseOffset = 4
        case 2:
            baseOffset = 2
        default:
            baseOffset = 0
        }

        return direction * baseOffset * viewModel.magnetSnapStrength
    }
}

private struct ActionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [NotchActionKind: CGRect] = [:]

    static func reduce(value: inout [NotchActionKind: CGRect], nextValue: () -> [NotchActionKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
