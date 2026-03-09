import SwiftUI
import UniformTypeIdentifiers

struct OverlayRootView: View {
    @ObservedObject var viewModel: NotchDockViewModel
    @State private var isCapsuleDropTargeted = false

    private var activeActions: [WorkActionKind] {
        viewModel.presentedActions.isEmpty ? WorkActionKind.allCases : viewModel.presentedActions
    }

    private var shouldRenderCapsule: Bool {
        if viewModel.isDragSessionActive {
            return true
        }
        return viewModel.presentationState != .hidden
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)
            if shouldRenderCapsule {
                capsule
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1), value: viewModel.presentationState)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.1), value: viewModel.isDragSessionActive)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.08), value: viewModel.targetedAction)
    }

    private var capsule: some View {
        VStack(spacing: 10) {
            if viewModel.presentationState == .expand || viewModel.presentationState == .processing {
                header
            }

            if viewModel.presentationState == .armed {
                armedHint
            }

            if viewModel.presentationState == .peek || viewModel.presentationState == .expand || viewModel.presentationState == .processing {
                IconStripView(icons: viewModel.visibleIcons, state: viewModel.presentationState)
                    .padding(.horizontal, 12)
                    .padding(.top, viewModel.presentationState == .peek ? 8 : 4)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
        .scaleEffect(viewModel.presentationState == .armed ? 1.02 : 1)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            viewModel.toggleExpand()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isCapsuleDropTargeted) { providers in
            loadURLs(from: providers) { urls in
                Task { @MainActor in
                    await viewModel.performDrop(inputs: urls, target: nil)
                }
            }
            return true
        }
    }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(viewModel.isDragSessionActive ? 0.15 : 0.1),
                                .white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }

    private var capsuleOutline: some View {
        Capsule(style: .continuous)
            .stroke(Color.white.opacity(viewModel.isDragSessionActive ? 0.28 : 0.22), lineWidth: 1)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(viewModel.targetedAction == nil ? 0 : 0.16), lineWidth: 2)
                    .blur(radius: 6)
            )
    }

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
            Text(viewModel.isDragSessionActive ? "Drop now or click a chip" : "Click to open actions or drag files onto the notch")
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
            Text("Compact")
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                } else if let string = item as? String {
                    resolved = URL(string: string)
                }
                if let resolved {
                    lock.lock()
                    urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}
