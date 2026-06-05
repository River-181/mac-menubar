import SwiftUI
import UniformTypeIdentifiers

struct DropHubView: View {
    let actions: [WorkActionKind]
    let recommendedAction: WorkActionKind?
    let interactionMode: OverlayInteractionMode
    let targetedAction: WorkActionKind?
    let showsRecommendedAction: Bool
    let disabledReasons: [WorkActionKind: String]
    let onRunAction: (WorkActionKind) -> Void
    let onTargetChange: (WorkActionKind?) -> Void
    let onDrop: (WorkActionKind, [URL]) -> Void

    var body: some View {
        Group {
            if interactionMode == .drag {
                dragLayout
            } else {
                clickLayout
            }
        }
    }

    private var clickLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            hubHeader(title: "Work Hub", subtitle: "Click a chip or drop files onto it")

            ForEach(sectionedActions) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.category.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(section.actions) { action in
                            chip(for: action, hero: false)
                        }
                    }
                }
            }
        }
    }

    private var dragLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            hubHeader(title: "Drop to Run", subtitle: "Keep dragging over the notch")

            if let recommendedAction {
                chip(for: recommendedAction, hero: true)
            }

            let secondary = dragSecondaryActions
            if !secondary.isEmpty {
                LazyVGrid(columns: dragColumns, spacing: 10) {
                    ForEach(secondary) { action in
                        chip(for: action, hero: false)
                    }
                }
            }
        }
    }

    private func chip(for action: WorkActionKind, hero: Bool) -> some View {
        DropChip(
            action: action,
            highlighted: targetedAction == action,
            emphasized: showsRecommendedAction && recommendedAction == action,
            interactionMode: interactionMode,
            disabledReason: disabledReasons[action],
            isHero: hero,
            onSelect: { onRunAction(action) },
            onTargetChange: onTargetChange,
            onDrop: { urls in onDrop(action, urls) }
        )
    }

    private func hubHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var sectionedActions: [ActionSection] {
        WorkActionCategory.allCases.compactMap { category in
            let items = actions.filter { $0.category == category }
            return items.isEmpty ? nil : ActionSection(category: category, actions: items)
        }
    }

    /// Two flexible columns so the grid produces 2 chips per row,
    /// matching the ViewModel's panel-height assumption of ceil(count/2) rows.
    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top)
        ]
    }

    private var dragColumns: [GridItem] {
        // Fixed 3-column grid to match the panel-height math in NotchDockViewModel.
        [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top)
        ]
    }

    private var dragSecondaryActions: [WorkActionKind] {
        actions.filter { $0 != recommendedAction }
    }
}

private struct ActionSection: Identifiable {
    let category: WorkActionCategory
    let actions: [WorkActionKind]

    var id: WorkActionCategory { category }
}

private struct DropChip: View {
    let action: WorkActionKind
    let highlighted: Bool
    let emphasized: Bool
    let interactionMode: OverlayInteractionMode
    let disabledReason: String?
    let isHero: Bool
    let onSelect: () -> Void
    let onTargetChange: (WorkActionKind?) -> Void
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Reduce-motion helpers

    private var chipScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return highlighted || isTargeted ? 1.035 : 1
    }

    private var chipYOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return highlighted || isTargeted ? -1 : 0
    }

    private var chipAnimation: Animation? {
        reduceMotion ? Animation?.none : .interactiveSpring(response: 0.24, dampingFraction: 0.84)
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: action.symbolName)
                    .font(.system(size: isHero ? 16 : 15, weight: .semibold))
                    .frame(width: isHero ? 32 : 28, height: isHero ? 32 : 28)
                    .background(
                        Circle()
                            .fill(iconBackground)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(.system(size: isHero ? 15 : 14, weight: .semibold))
                            .lineLimit(1)
                        if emphasized && !highlighted && !isTargeted {
                            Text("Best")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.72))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, isHero ? 16 : 14)
            .padding(.vertical, isHero ? 14 : 12)
            .frame(minHeight: isHero ? 64 : 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(chipScale)
            .offset(y: chipYOffset)
            .shadow(color: .black.opacity(highlighted || isTargeted ? 0.18 : 0.08), radius: highlighted || isTargeted ? 12 : (isHero ? 10 : 6), x: 0, y: highlighted || isTargeted ? 8 : (isHero ? 5 : 3))
        }
        .buttonStyle(.plain)
        .disabled(disabledReason != nil)
        .opacity(disabledReason == nil ? 1 : 0.6)
        .accessibilityLabel(action.title)
        .accessibilityHint(disabledReason == nil ? "Runs this action on the dropped files" : "")
        .accessibilityAddTraits(.isButton)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            guard disabledReason == nil else { return false }
            DropPayload.loadFileURLs(from: providers, completion: onDrop)
            return true
        }
        .onChange(of: isTargeted) { _, value in
            guard disabledReason == nil else { return }
            onTargetChange(value ? action : nil)
        }
        .animation(chipAnimation, value: highlighted)
        .animation(chipAnimation, value: isTargeted)
    }

    private var subtitle: String {
        if let disabledReason {
            return disabledReason
        }
        if highlighted || isTargeted {
            return "Release to run"
        }
        if emphasized {
            return "Recommended for current files"
        }
        return interactionMode == .drag ? "Keep dragging to target" : "Click or drop to run"
    }

    private var backgroundFill: Color {
        if highlighted || isTargeted {
            return .white.opacity(0.22)
        }
        if isHero {
            return .white.opacity(0.16)
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
        if isHero {
            return .white.opacity(0.16)
        }
        return .white.opacity(0.12)
    }
}
