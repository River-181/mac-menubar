import Foundation

struct IconDockArrangement: Equatable {
    let visible: [DockIcon]
    let overflow: [DockIcon]
    let grouped: [String: [DockIcon]]
}

final class IconDockService {
    func score(for icon: DockIcon, now: Date = .now) -> Double {
        let pinnedWeight = icon.bucket == .pinned ? 1000.0 : 0
        let rankWeight = icon.rank * 100
        let recencySeconds = max(0, now.timeIntervalSince(icon.lastUsedAt))
        let recencyWeight = max(0, 300 - recencySeconds) / 3
        return pinnedWeight + rankWeight + recencyWeight
    }

    func sort(_ icons: [DockIcon], now: Date = .now) -> [DockIcon] {
        icons.sorted { lhs, rhs in
            let lhsScore = score(for: lhs, now: now)
            let rhsScore = score(for: rhs, now: now)
            if lhsScore == rhsScore {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhsScore > rhsScore
        }
    }

    func arrange(
        pinned: [DockIcon],
        shelf: [DockIcon],
        state: DockOverlayState
    ) -> IconDockArrangement {
        let now = Date()
        let sortedPinned = sort(pinned, now: now)
        let sortedShelf = sort(shelf, now: now)
        let capacity: Int
        switch state {
        case .idle:
            capacity = 3
        case .peek:
            capacity = 7
        case .expand, .grab, .focus:
            capacity = 20
        case .workspace:
            capacity = 24
        }

        let all = sortedPinned + sortedShelf
        let visible = Array(all.prefix(capacity))
        let overflow = Array(all.dropFirst(capacity)).map { icon in
            var updated = icon
            updated.bucket = .overflow
            return updated
        }

        let grouped = Dictionary(grouping: visible, by: \.groupID)
        return IconDockArrangement(visible: visible, overflow: overflow, grouped: grouped)
    }
}
