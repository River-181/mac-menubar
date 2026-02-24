import SwiftUI
import UniformTypeIdentifiers

struct OverlayRootView: View {
    @ObservedObject var viewModel: NotchDockViewModel
    @State private var isCapsuleDropTargeted = false

    private var activeActions: [WorkActionKind] {
        let primary = viewModel.dropPlan.recommendedAction.map { [$0] } ?? []
        let merged = primary + viewModel.dropPlan.secondaryActions
        return merged.isEmpty ? WorkActionKind.allCases : merged
    }

    private var shouldRenderCapsule: Bool {
        if viewModel.isDragSessionActive {
            return true
        }
        return viewModel.overlayState != .hidden && viewModel.overlayState != .armed
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
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1), value: viewModel.overlayState)
    }

    private var capsule: some View {
        VStack(spacing: 10) {
            if viewModel.overlayState == .expand || viewModel.overlayState == .processing {
                header
            }

            if viewModel.overlayState != .armed {
                IconStripView(icons: viewModel.visibleIcons, state: viewModel.overlayState)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            if viewModel.overlayState == .expand || viewModel.overlayState == .processing || viewModel.isDragSessionActive {
                DropHubView(
                    actions: activeActions,
                    targetedAction: viewModel.targetedAction,
                    onRunAction: { action in
                        Task { @MainActor in
                            await viewModel.performActionFromPicker(action)
                        }
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
        .frame(width: viewModel.overlayState.capsuleSize.width, alignment: .top)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
        .scaleEffect(viewModel.overlayState == .armed ? 1.02 : 1)
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
