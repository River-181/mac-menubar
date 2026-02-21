import Foundation

#if canImport(Combine)
import Combine
private typealias MBObservableObject = ObservableObject
#else
private protocol MBObservableObject {}
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

final class MenuBarViewModel: MBObservableObject {
    enum VisibilityGroup: String, Codable, CaseIterable {
        case alwaysVisible
        case smartHide
        case hidden
    }

    struct MenuBarIcon: Identifiable, Codable, Equatable {
        let id: String
        var name: String
        var width: CGFloat
        var priority: Int
        var minimumWidth: CGFloat
        var lastInteractionAt: Date
        var visibilityGroup: VisibilityGroup

        mutating func registerInteraction(at date: Date = Date()) {
            lastInteractionAt = date
        }
    }

    #if canImport(Combine)
    @Published
    #endif
    private(set) var icons: [MenuBarIcon] {
        didSet { persistSettings() }
    }

    #if canImport(Combine)
    @Published
    #endif
    private(set) var visibleIcons: [MenuBarIcon] = []

    private let defaults: UserDefaults
    private let storageKey = "menuBar.iconSettings.v1"

    init(
        defaultIcons: [MenuBarIcon],
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.icons = defaultIcons
        restoreSettings()
        applyVisibilityPolicy(availableWidth: .greatestFiniteMagnitude, isActive: true, animated: false)
    }

    func applyVisibilityPolicy(
        availableWidth: CGFloat,
        isActive: Bool,
        animated: Bool = true
    ) {
        let nextVisible = buildVisibleIcons(availableWidth: availableWidth, isActive: isActive)

        let update = {
            self.visibleIcons = nextVisible
        }

        if animated {
            runVisibilityAnimation(update)
        } else {
            update()
        }
    }

    func updateGroup(iconID: String, group: VisibilityGroup) {
        guard let index = icons.firstIndex(where: { $0.id == iconID }) else { return }
        icons[index].visibilityGroup = group
    }

    func updatePriority(iconID: String, priority: Int) {
        guard let index = icons.firstIndex(where: { $0.id == iconID }) else { return }
        icons[index].priority = priority
    }

    func registerInteraction(iconID: String, at date: Date = Date()) {
        guard let index = icons.firstIndex(where: { $0.id == iconID }) else { return }
        icons[index].registerInteraction(at: date)
    }

    private func buildVisibleIcons(availableWidth: CGFloat, isActive: Bool) -> [MenuBarIcon] {
        // 1) Hidden: 기본 비표시
        let alwaysVisibleIcons = icons
            .filter { $0.visibilityGroup == .alwaysVisible }
            .sorted(using: iconSort)
        let smartHideIcons = icons
            .filter { $0.visibilityGroup == .smartHide }
            .sorted(using: iconSort)

        // 2) Smart Hide: 비활성 시 숨김
        var candidates = alwaysVisibleIcons
        if isActive {
            candidates.append(contentsOf: smartHideIcons)
        }

        // 3) 공간 부족 시 Smart Hide를 먼저 제거하고 Always Visible은 마지막까지 유지
        var widthUsed: CGFloat = candidates.reduce(0) { $0 + max($1.width, $1.minimumWidth) }
        if widthUsed > availableWidth {
            let dropOrder = candidates.sorted { lhs, rhs in
                policyScore(for: lhs) < policyScore(for: rhs)
            }

            var remaining: [String: Bool] = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, true) })
            for icon in dropOrder where widthUsed > availableWidth {
                if remaining[icon.id] == true {
                    remaining[icon.id] = false
                    widthUsed -= max(icon.width, icon.minimumWidth)
                }
            }

            candidates = candidates.filter { remaining[$0.id] == true }
        }

        return candidates.sorted(using: iconSort)
    }

    private func policyScore(for icon: MenuBarIcon) -> Int {
        // 낮은 점수일수록 먼저 숨김 처리
        switch icon.visibilityGroup {
        case .hidden:
            return 0
        case .smartHide:
            return 1
        case .alwaysVisible:
            return 2
        }
    }

    private var iconSort: KeyPathComparator<MenuBarIcon> {
        KeyPathComparator(\.priority, order: .reverse)
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(icons) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func restoreSettings() {
        guard
            let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode([MenuBarIcon].self, from: data)
        else { return }

        var map = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        icons = icons.map { current in
            map.removeValue(forKey: current.id) ?? current
        }
    }

    private func runVisibilityAnimation(_ changes: @escaping () -> Void) {
        #if canImport(SwiftUI)
        withAnimation(.easeInOut(duration: 0.2), changes)
        #else
        changes()
        #endif
    }
}
