import SwiftUI

struct NotchDropZoneView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionFrames: [NotchActionKind: CGRect] = [:]
    @State private var currentPanelWidth: CGFloat = 520
    @State private var pendingTargetExit: DispatchWorkItem?

    private let triggerHeight: CGFloat = 44
    private let triggerTopPadding: CGFloat = 6
    private let compactHeight: CGFloat = 26
    private let expandedHeight: CGFloat = 198
    private let panelWidth: CGFloat = 520
    private let preHoverDelay: TimeInterval = 0.04
    private let hoverExitDelay: TimeInterval = 0.08
    private let strictHeight: CGFloat = 34
    private let looseHeight: CGFloat = 52

    private enum IslandPhase: Int {
        case hidden
        case compact
        case expanded
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(panelWidth, proxy.size.width)
            ZStack(alignment: .top) {
                Color.clear
                    .frame(height: triggerHeight + (triggerTopPadding * 2))
                    .contentShape(Rectangle())
                    .onAppear {
                        currentPanelWidth = width
                    }
                    .onChange(of: width) {
                        currentPanelWidth = width
                    }

                if islandPhase != .hidden {
                    islandSurface
                        .frame(height: islandHeight)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .allowsHitTesting(true)
                        .animation(islandAnimation, value: islandPhase)
                }
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "drop-zone")
            .background(dropTrackingOverlay)
            .onContinuousHover { phase in
                guard case .active(let point) = phase else {
                    if case .ended = phase {
                        cancelTargetExit()
                        viewModel.setDropTargetAreaActive(false)
                        if !viewModel.dragSession.isFileDrag {
                            viewModel.setDropZoneHover(false)
                        }
                    }
                    return
                }

                let strict = isPointInNotchTarget(point, panelWidth: width, strict: true)
                let loose = isPointInNotchTarget(point, panelWidth: width, strict: false)

                if strict {
                    cancelTargetExit()
                    if !viewModel.isDropTargetAreaActive {
                        DispatchQueue.main.asyncAfter(deadline: .now() + preHoverDelay) {
                            guard isPointInNotchTarget(point, panelWidth: width, strict: true) else { return }
                            viewModel.setDropTargetAreaActive(true)
                        }
                    } else {
                        viewModel.setDropTargetAreaActive(true)
                    }
                    viewModel.setDropZoneHover(true)
                    return
                }

                if loose {
                    if viewModel.isDropTargetAreaActive {
                        cancelTargetExit()
                    }
                    return
                }

                if viewModel.isDropZoneHovered || viewModel.isDropTargetAreaActive {
                    cancelTargetExit()
                    scheduleTargetExit()
                }
            }
            .onPreferenceChange(ActionFramePreferenceKey.self) { actionFrames = $0 }
        }
    }

    private var dropTrackingOverlay: some View {
        DropTrackingView(
            onDragEntered: { point, urls in
                let inTarget = isPointInNotchTarget(point, panelWidth: currentPanelWidth, strict: true)
                viewModel.setDropTargetAreaActive(inTarget)
                viewModel.beginDragSession(with: urls, shouldReveal: inTarget)
            },
            onDragUpdated: { point, dynamics in
                let inTarget = isPointInNotchTarget(point, panelWidth: currentPanelWidth, strict: true)
                if viewModel.isDropTargetAreaActive != inTarget {
                    viewModel.setDropTargetAreaActive(inTarget)
                    if !inTarget {
                        viewModel.updateDragTarget(nil)
                    }
                }

                guard inTarget else {
                    return
                }

                viewModel.updateDragDynamics(dynamics)
                viewModel.updateDragTarget(action(at: point))
            },
            onDragExited: {
                viewModel.setDropTargetAreaActive(false)
                viewModel.setDropZoneHover(false)
                viewModel.endDragSession()
            },
            onPerformDrop: { urls, point in
                guard viewModel.isDropTargetAreaActive else {
                    viewModel.endDragSession()
                    return
                }
                let targeted = action(at: point)
                viewModel.handleDroppedItems(urls, preferredAction: targeted)
            }
        )
        .allowsHitTesting(true)
        .opacity(0.01)
    }

    private func scheduleTargetExit() {
        cancelTargetExit()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.setDropZoneHover(false)
            self.viewModel.setDropTargetAreaActive(false)
        }
        pendingTargetExit = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverExitDelay, execute: item)
    }

    private func cancelTargetExit() {
        pendingTargetExit?.cancel()
        pendingTargetExit = nil
    }

    private func isTargetWidth(panelWidth: CGFloat, strict: Bool) -> CGFloat {
        let viewWidth = max(1, panelWidth)
        let rawWidth = viewModel.layoutSnapshot.notchWidth > 0
            ? viewModel.layoutSnapshot.notchWidth + (strict ? 24 : 44)
            : (strict ? 112 : 140)
        return min(max(strict ? 96 : 120, rawWidth), min(strict ? 190 : 220, viewWidth - 72))
    }

    private func isTargetHeight(strict: Bool) -> CGFloat {
        strict ? strictHeight : looseHeight
    }

    private func isPointInNotchTarget(_ point: CGPoint, panelWidth: CGFloat, strict: Bool) -> Bool {
        let viewWidth = max(1, panelWidth)
        let targetWidth = isTargetWidth(panelWidth: viewWidth, strict: strict)
        let centerX = viewWidth / 2
        let half = targetWidth / 2
        let yLimit = isTargetHeight(strict: strict)

        return point.x >= (centerX - half) && point.x <= (centerX + half) &&
            point.y >= 0 && point.y <= yLimit
    }

    private var islandPhase: IslandPhase {
        guard viewModel.isDropTargetAreaActive else {
            return .hidden
        }

        switch viewModel.dropVisualPhase {
        case .idle:
            return .hidden
        case .hoverReveal, .dragReveal:
            return .compact
        case .tracking, .lock(_), .commit(_), .processing, .result:
            return .expanded
        }
    }

    private var isIslandCompact: Bool {
        islandPhase == .compact
    }

    private var islandExpanded: Bool {
        islandPhase == .expanded
    }

    private var islandHeight: CGFloat {
        islandExpanded ? expandedHeight : compactHeight
    }

    private var islandSurface: some View {
        VStack(alignment: .center, spacing: isIslandCompact ? 0 : 8) {
            dragHandle
                .padding(.top, isIslandCompact ? 5 : 6)
                .padding(.bottom, isIslandCompact ? 4 : 6)

            if islandExpanded {
                expandedContent
                    .padding(.bottom, 2)
                    .clipped()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isIslandCompact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 0.95)
                )
        )
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(color: Color.black.opacity(0.11), radius: 18, x: 0, y: 4)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(.primary.opacity(0.16))
            .frame(width: 54, height: 3.5)
            .frame(maxWidth: .infinity)
            .shadow(
                color: .black.opacity(islandExpanded ? 0.13 : 0.08),
                radius: isIslandCompact ? 2 : 4,
                x: 0,
                y: 1
            )
            .blur(radius: isIslandCompact ? 0.2 : 0.0)
    }

    private var expandedContent: some View {
        VStack(alignment: .center, spacing: 8) {
            LazyVGrid(columns: actionColumns, spacing: 8) {
                ForEach(NotchActionKind.allCases) { action in
                    actionChip(action)
                }
            }
            .frame(maxWidth: .infinity)

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
        return "Drop files here for fast actions."
    }

    @ViewBuilder
    private func actionChip(_ action: NotchActionKind) -> some View {
        let isAvailable = viewModel.availableDropActions.contains(action)
        let isProcessing = viewModel.notchDropState == .processing
        let isTargeted = viewModel.targetedDropAction == action
        let isRecommended = viewModel.recommendedDropAction == action && viewModel.targetedDropAction == nil && viewModel.dragSession.isFileDrag
        let magnet = magnetEffect(for: action, isTargeted: isTargeted)
        let neighborOffset = magnet.offsetX
        let targetLift = magnet.offsetY
        let targetScale = magnet.scale
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
        if let direct = actionFrames.first(where: { pair in
            pair.value.contains(point) && viewModel.availableDropActions.contains(pair.key)
        })?.key {
            return direct
        }

        let snapRadius: CGFloat = 34
        var nearest: (action: NotchActionKind, distance: CGFloat)?

        for (action, frame) in actionFrames where viewModel.availableDropActions.contains(action) {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let distance = sqrt((dx * dx) + (dy * dy))
            guard distance <= snapRadius else { continue }
            if let existing = nearest {
                if distance < existing.distance {
                    nearest = (action, distance)
                }
            } else {
                nearest = (action, distance)
            }
        }

        return nearest?.action
    }

    private var actionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 56, maximum: 72), spacing: 8), count: 5)
    }

    private var islandAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return .interactiveSpring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.10)
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

    private func magnetEffect(for action: NotchActionKind, isTargeted: Bool) -> (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        guard viewModel.interactiveMagnetEnabled else { return (1, 0, 0) }
        guard let frame = actionFrames[action] else {
            return isTargeted ? (1.04, 0, -2) : (1, 0, 0)
        }

        let pointer = viewModel.dragDynamics.lastPoint
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let dx = center.x - pointer.x
        let dy = center.y - pointer.y
        let distance = sqrt((dx * dx) + (dy * dy))
        let influenceRadius: CGFloat = 120
        let normalized = max(0, 1 - (distance / influenceRadius))
        let velocity = viewModel.dragDynamics.velocity
        let velocityLength = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        let centerLength = max(distance, 1)
        let dirToCenter = CGPoint(x: dx / centerLength, y: dy / centerLength)
        let dirVelocity = CGPoint(
            x: velocityLength > 0.0001 ? velocity.x / velocityLength : 0,
            y: velocityLength > 0.0001 ? velocity.y / velocityLength : 0
        )
        let directionDot = (dirToCenter.x * dirVelocity.x) + (dirToCenter.y * dirVelocity.y)
        let alignmentBoost = max(0, directionDot)
        let directionFactor = (0.78 + (alignmentBoost * 0.22)) * (directionDot < 0 ? 0.74 : 1)
        let strength = normalized * viewModel.magnetSnapStrength * directionFactor

        if isTargeted {
            let scale = 1 + (0.05 * max(strength, 0.7))
            let lift = -2.6 * max(strength, 0.7)
            return (scale, 0, lift)
        }

        let damped = min(1, strength * 0.7)
        let offsetX = dx == 0 ? 0 : ((-dx / max(distance, 1)) * 3.6 * damped)
        let offsetY = dy == 0 ? 0 : ((-dy / max(distance, 1)) * 2.2 * damped)
        let scale = 1 + (0.015 * damped)
        return (scale, offsetX, offsetY)
    }
}

private struct ActionFramePreferenceKey: PreferenceKey {
    static let defaultValue: [NotchActionKind: CGRect] = [:]

    static func reduce(value: inout [NotchActionKind: CGRect], nextValue: () -> [NotchActionKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
