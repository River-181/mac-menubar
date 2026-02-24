import SwiftUI
import UniformTypeIdentifiers

struct OverlayRootView: View {
    @ObservedObject var viewModel: NotchDockViewModel
    @State private var isCapsuleDropTargeted = false
    @State private var isWorkspaceDropTargeted = false

    private var capsuleSize: CGSize {
        viewModel.overlayState.capsuleSize
    }

    private var actionTargets: [WorkActionKind] {
        let plan = viewModel.dropPlan
        let primary = plan.recommendedAction.map { [$0] } ?? []
        let all = primary + plan.secondaryActions
        return all.isEmpty ? WorkActionKind.allCases : all
    }

    private var shouldRenderCapsule: Bool {
        viewModel.overlayState != .idle || viewModel.isNearTopTrigger || viewModel.isDragSessionActive
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if shouldRenderCapsule {
                    capsule
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .animation(
            viewModel.reduceMotionEnabled
                ? .easeInOut(duration: 0.12)
                : .interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.10),
            value: viewModel.overlayState
        )
        .onChange(of: isCapsuleDropTargeted) { _, targeted in
            if targeted {
                viewModel.prepareDropPreview()
            }
        }
    }

    private var shouldShowHeader: Bool {
        switch viewModel.overlayState {
        case .expand, .grab, .focus, .workspace:
            return true
        case .idle, .peek:
            return false
        }
    }

    private var capsule: some View {
        VStack(spacing: 8) {
            if shouldShowHeader {
                header
            }

            IconStripView(
                icons: viewModel.visibleIcons,
                state: viewModel.overlayState,
                spacing: viewModel.effectiveSpacing,
                onReorder: { source, target in
                    viewModel.reorderIcon(source, before: target)
                },
                onUse: { iconID in
                    viewModel.markIconUsed(iconID)
                },
                onFocus: { iconID in
                    viewModel.transition(.focusIcon(iconID))
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, viewModel.overlayState == .idle ? 3 : 2)

            if viewModel.overlayState == .expand
                || viewModel.overlayState == .grab
                || viewModel.overlayState == .focus
                || (viewModel.isDragSessionActive && viewModel.overlayState == .peek) {
                workHubTargets
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            if viewModel.overlayState == .workspace {
                workspaceCanvas
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let toast = viewModel.dropToast {
                toastView(toast)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: capsuleSize.width, alignment: .top)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .scaleEffect(viewModel.isNearTopTrigger && viewModel.overlayState == .idle ? 1.02 : 1)
        .onTapGesture(count: 2) {
            if viewModel.enableWorkspace {
                viewModel.toggleWorkspace(trigger: .doubleClick)
            }
        }
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
        .allowsHitTesting(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("NotchDock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(viewModel.effectiveCompactMode ? "Compact" : "Respect")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if let activeGroup = viewModel.activeGroupFilter {
                Text(activeGroup)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(.white.opacity(0.14)))
            }
            if viewModel.enableWorkspace {
                Button {
                    viewModel.toggleWorkspace(trigger: .hotkey)
                } label: {
                    Image(systemName: viewModel.overlayState == .workspace ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .buttonStyle(.plain)
            }
            Button {
                viewModel.closeOneLevel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
    }

    private var workHubTargets: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: viewModel.overlayState == .peek ? 150 : 160), spacing: 8),
            count: viewModel.overlayState == .peek ? 2 : 3
        )

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(actionTargets, id: \.rawValue) { action in
                ActionDropChip(
                    action: action,
                    isMagnetFocused: viewModel.targetedDropAction == action,
                    onSelect: {
                        Task { @MainActor in
                            await viewModel.performActionFromPicker(action)
                        }
                    },
                    onDropURLs: { urls in
                    Task { @MainActor in
                        await viewModel.performDrop(inputs: urls, target: action)
                    }
                }
                )
            }
        }
    }

    private var workspaceCanvas: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Workspace")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button("Add Files") {
                            Task { @MainActor in
                                await viewModel.performActionFromPicker(.sendToWorkbench)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if viewModel.workspaceCards.isEmpty {
                        Text("Drag files here or tap Add Files. Stored files are shown as cards.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 8), count: 3), spacing: 8) {
                                ForEach(viewModel.workspaceCards) { card in
                                    workspaceCardView(card)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(isWorkspaceDropTargeted ? 0.38 : 0.12), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isWorkspaceDropTargeted) { providers in
                loadURLs(from: providers) { urls in
                    Task { @MainActor in
                        await viewModel.performDrop(inputs: urls, target: .sendToWorkbench)
                    }
                }
                return true
            }
    }

    private func workspaceCardView(_ card: WorkspaceCard) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForCard(card))
                .font(.system(size: 12, weight: .semibold))
            Text(card.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                viewModel.openWorkspaceCard(card.id)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            Button {
                viewModel.removeWorkspaceCard(card.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func iconForCard(_ card: WorkspaceCard) -> String {
        guard let url = card.fileURL else { return "doc" }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff"].contains(ext) {
            return "photo"
        }
        if ext == "pdf" {
            return "doc.richtext"
        }
        if ext == "zip" {
            return "archivebox"
        }
        return "doc"
    }

    private func toastView(_ toast: DropToast) -> some View {
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
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolvedURL: URL?
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolvedURL = url
                } else if let url = item as? URL {
                    resolvedURL = url
                } else if let string = item as? String, let url = URL(string: string) {
                    resolvedURL = url
                }
                if let resolvedURL {
                    lock.lock()
                    urls.append(resolvedURL)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }
}

private struct ActionDropChip: View {
    let action: WorkActionKind
    let isMagnetFocused: Bool
    let onSelect: () -> Void
    let onDropURLs: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.symbolName)
                .font(.system(size: 12, weight: .semibold))
            Text(action.displayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity((isTargeted || isMagnetFocused) ? 0.20 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity((isTargeted || isMagnetFocused) ? 0.38 : 0.18), lineWidth: 1)
        )
        .scaleEffect((isTargeted || isMagnetFocused) ? 1.03 : 1)
        .shadow(
            color: .black.opacity((isTargeted || isMagnetFocused) ? 0.22 : 0.12),
            radius: (isTargeted || isMagnetFocused) ? 8 : 4,
            x: 0,
            y: (isTargeted || isMagnetFocused) ? 4 : 2
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isTargeted)
        .animation(.easeOut(duration: 0.14), value: isMagnetFocused)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadURLs(from: providers, onDropURLs: onDropURLs)
        }
    }

    private func loadURLs(from providers: [NSItemProvider], onDropURLs: @escaping ([URL]) -> Void) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolved = url
                } else if let url = item as? URL {
                    resolved = url
                } else if let string = item as? String, let url = URL(string: string) {
                    resolved = url
                }
                if let resolved {
                    lock.lock()
                    urls.append(resolved)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            onDropURLs(urls)
        }
        return true
    }
}
