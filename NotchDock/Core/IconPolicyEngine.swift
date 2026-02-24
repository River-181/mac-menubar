import Foundation

final class IconPolicyEngine: IconPolicyProviding {
    func arrange(icons: [DockIcon], state: OverlayState) -> IconPolicyResult {
        let enabled = icons
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.bucket != rhs.bucket {
                    return lhs.bucket == .pinned
                }
                if lhs.rank == rhs.rank {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.rank < rhs.rank
            }

        let visibleLimit: Int
        switch state {
        case .hidden:
            visibleLimit = 0
        case .armed:
            visibleLimit = 2
        case .peek:
            visibleLimit = 6
        case .expand, .processing:
            visibleLimit = 14
        }

        let visible = Array(enabled.prefix(visibleLimit))
        let overflow = Array(enabled.dropFirst(visibleLimit)).map { icon in
            var mutable = icon
            mutable.bucket = .overflow
            return mutable
        }
        return IconPolicyResult(visible: visible, overflow: overflow)
    }
}
