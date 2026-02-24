import Defaults
import Foundation

enum NotchDockDefaults {
    static let selectedIconIDs = Defaults.Key<[String]>(
        "notchdock_selected_icon_ids_v1",
        default: ["wifi", "battery", "volume", "clock"]
    )
}

final class IconSourceService: IconSourceProviding {
    static let candidateIcons: [DockIcon] = [
        DockIcon(id: "wifi", title: "Wi-Fi", symbolName: "wifi", bucket: .pinned, rank: 0, isEnabled: true),
        DockIcon(id: "battery", title: "Battery", symbolName: "battery.100", bucket: .pinned, rank: 1, isEnabled: true),
        DockIcon(id: "volume", title: "Volume", symbolName: "speaker.wave.2", bucket: .pinned, rank: 2, isEnabled: true),
        DockIcon(id: "clock", title: "Clock", symbolName: "clock", bucket: .pinned, rank: 3, isEnabled: true),
        DockIcon(id: "vpn", title: "VPN", symbolName: "lock.shield", bucket: .shelf, rank: 4, isEnabled: true),
        DockIcon(id: "terminal", title: "Terminal", symbolName: "terminal", bucket: .shelf, rank: 5, isEnabled: true),
        DockIcon(id: "music", title: "Music", symbolName: "music.note", bucket: .shelf, rank: 6, isEnabled: true),
        DockIcon(id: "folder", title: "Files", symbolName: "folder", bucket: .shelf, rank: 7, isEnabled: true)
    ]

    func fetchPinnedCandidates() async -> [DockIcon] {
        Self.candidateIcons
    }

    func fetchUserSelectedIcons() async -> [DockIcon] {
        let selected = Set(Defaults[NotchDockDefaults.selectedIconIDs])
        return Self.candidateIcons.enumerated().compactMap { index, icon in
            guard selected.contains(icon.id) else { return nil }
            var mutable = icon
            mutable.rank = index
            mutable.bucket = index < 4 ? .pinned : .shelf
            return mutable
        }
    }

    func setEnabled(_ iconID: String, enabled: Bool) {
        var selected = Defaults[NotchDockDefaults.selectedIconIDs]
        if enabled {
            if !selected.contains(iconID) {
                selected.append(iconID)
            }
        } else {
            selected.removeAll { $0 == iconID }
        }
        Defaults[NotchDockDefaults.selectedIconIDs] = selected
    }
}
