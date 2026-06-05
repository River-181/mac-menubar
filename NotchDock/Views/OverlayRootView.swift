import SwiftUI
import UniformTypeIdentifiers

struct OverlayRootView: View {
    @ObservedObject var viewModel: NotchDockViewModel
    @State private var isCapsuleDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var activeActions: [WorkActionKind] {
        viewModel.presentedActions.isEmpty ? WorkActionKind.allCases : viewModel.presentedActions
    }

    private var shouldRenderCapsule: Bool {
        if viewModel.isDragSessionActive {
            return true
        }
        return viewModel.presentationState != .hidden
    }

    // MARK: - Reduce-motion helpers

    private var capsuleTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private var hubTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)
            if shouldRenderCapsule {
                capsule
                    .padding(.top, 8)
                    .transition(capsuleTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1), value: viewModel.presentationState)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.1), value: viewModel.isDragSessionActive)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.08), value: viewModel.targetedAction)
    }

    // MARK: - Capsule

    private var capsule: some View {
        VStack(spacing: 10) {
            if viewModel.presentationState == .expand || viewModel.presentationState == .processing {
                header
            }

            if viewModel.presentationState == .armed {
                armedHint
            }

            if viewModel.presentationState == .peek && !viewModel.isDragSessionActive {
                compactHint
                    .padding(.horizontal, 14)
            }

            if viewModel.presentationState == .expand || viewModel.presentationState == .processing || viewModel.isDragSessionActive {
                DropHubView(
                    actions: activeActions,
                    recommendedAction: viewModel.dropPlan.recommendedAction,
                    interactionMode: viewModel.interactionMode,
                    targetedAction: viewModel.targetedAction,
                    showsRecommendedAction: viewModel.isRecommendedActionVisible,
                    disabledReasons: viewModel.actionDisabledReasons,
                    onRunAction: { action in
                        Task { @MainActor in
                            await viewModel.performActionFromPicker(action)
                        }
                    },
                    onTargetChange: { action in
                        viewModel.setHoveredAction(action)
                    },
                    onDrop: { action, urls in
                        Task { @MainActor in
                            await viewModel.performDrop(inputs: urls, target: action)
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(hubTransition)
            }

            if let toast = viewModel.toast {
                toastView(toast)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: viewModel.panelSize.width - 16, alignment: .top)
        .padding(.vertical, 8)
        .background(capsuleBackground)
        .overlay(capsuleOutline)
        .overlay(alignment: .top) {
            notchBridge
        }
        .shadow(color: .black.opacity(0.30), radius: 20, x: 0, y: 12)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .scaleEffect((!reduceMotion && viewModel.presentationState == .armed) ? 1.02 : 1)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            viewModel.toggleExpand()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isCapsuleDropTargeted) { providers in
            DropPayload.loadFileURLs(from: providers) { urls in
                Task { @MainActor in
                    await viewModel.performDrop(inputs: urls, target: nil)
                }
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("NotchDock work hub")
    }

    // MARK: - Background & outline

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(viewModel.isDragSessionActive ? 0.17 : 0.11),
                                .white.opacity(0.06),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.06))
                    .blur(radius: 22)
                    .offset(y: -18)
                    .mask(
                        Capsule(style: .continuous)
                            .frame(height: 28)
                            .offset(y: -6)
                    )
            )
    }

    private var borderBaseOpacity: Double {
        let active = viewModel.isDragSessionActive
        return colorScheme == .dark
            ? (active ? 0.30 : 0.22)
            : (active ? 0.18 : 0.12)
    }

    private var borderBaseColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.3)
    }

    private var capsuleOutline: some View {
        Capsule(style: .continuous)
            .strokeBorder(borderBaseColor.opacity(borderBaseOpacity), lineWidth: 1)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(viewModel.targetedAction == nil ? 0 : 0.16), lineWidth: 2)
                    .blur(radius: 6)
            )
    }

    // MARK: - Notch bridge

    private var notchBridge: some View {
        Capsule(style: .continuous)
            .fill(.black.opacity(0.90))
            .frame(width: bridgeWidth, height: 18)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
            .offset(y: -11)
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
    }

    private var bridgeWidth: CGFloat {
        switch viewModel.presentationState {
        case .armed:
            return 118
        case .peek:
            return 138
        case .expand, .processing:
            return 168
        case .hidden:
            return 110
        }
    }

    // MARK: - Sub-views

    private var armedHint: some View {
        HStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.22))
                .frame(width: 54, height: 6)
            Text(viewModel.isDragSessionActive ? "Keep dragging on the notch" : "Hover, click, or drag files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var compactHint: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isDragSessionActive ? "arrow.down.circle.fill" : "hand.tap")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(viewModel.isDragSessionActive ? "Drop now or refine the target below" : "Click for the full hub or drag files onto the notch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("NotchDock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.interactionMode == .drag ? "Drag Flow" : "Compact")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Button {
                viewModel.closeOneLevel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func toastView(_ toast: OverlayToast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .red : .green)
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
            if viewModel.canUndoDangerousAction {
                Button("Undo") {
                    Task { @MainActor in
                        await viewModel.undoLastDangerousAction()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Undo last action")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}
