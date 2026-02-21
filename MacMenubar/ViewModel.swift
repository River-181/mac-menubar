import Foundation
import AppKit
import Combine

enum VisibilityGroup: String, Codable, CaseIterable {
    case alwaysVisible
    case smartHide
    case hidden
}

struct MenuBarIcon: Identifiable, Codable {
    let id: String
    var title: String
    var group: VisibilityGroup
    var priority: Int
    var minimumWidth: CGFloat
    var lastInteractionAt: Date
    var isVisible: Bool
}

struct TodoItem: Codable, Identifiable {
    let id: UUID
    var title: String
    var dueDate: Date?
    var isDone: Bool
}

final class MenuBarViewModel: ObservableObject {
    @Published var icons: [MenuBarIcon] = [
        .init(id: "wifi", title: "Wi-Fi", group: .alwaysVisible, priority: 100, minimumWidth: 36, lastInteractionAt: .now, isVisible: true),
        .init(id: "battery", title: "Battery", group: .alwaysVisible, priority: 90, minimumWidth: 42, lastInteractionAt: .now, isVisible: true),
        .init(id: "music", title: "Music", group: .smartHide, priority: 80, minimumWidth: 36, lastInteractionAt: .now, isVisible: true),
        .init(id: "clock", title: "Clock", group: .alwaysVisible, priority: 70, minimumWidth: 44, lastInteractionAt: .now, isVisible: true),
        .init(id: "vpn", title: "VPN", group: .hidden, priority: 10, minimumWidth: 30, lastInteractionAt: .now, isVisible: false)
    ]

    @Published var spacing: CGFloat = 8
    @Published var isPanelEnabled = true
    @Published var showSystemStats = true
    @Published var useAccentTheme = true
    @Published var batteryPercentage: Int = 0
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var todayEvents: [String] = []
    @Published var todos: [TodoItem] = []

    private let defaultsKey = "menubar.icon.configuration"
    private let taskStore = TaskStore()

    init() {
        loadConfiguration()
        todos = taskStore.load()
    }

    func recalculateLayout(availableWidth: CGFloat, activeAppIsFullscreen: Bool) {
        spacing = activeAppIsFullscreen ? 4 : max(6, min(14, availableWidth / 180))
        let requiredWidth = icons
            .filter { $0.group != .hidden }
            .reduce(CGFloat(0)) { $0 + $1.minimumWidth + spacing }

        guard requiredWidth > availableWidth else {
            icons = icons.map {
                var mutable = $0
                mutable.isVisible = $0.group != .hidden
                return mutable
            }
            persistConfiguration()
            return
        }

        let sorted = icons.sorted { lhs, rhs in
            if lhs.group == rhs.group { return lhs.priority > rhs.priority }
            return rank(lhs.group) > rank(rhs.group)
        }

        var width: CGFloat = 0
        var visibility = [String: Bool]()
        for icon in sorted {
            let shouldRenderByGroup = icon.group != .hidden
            let nextWidth = width + icon.minimumWidth + spacing
            let fits = nextWidth <= availableWidth
            let visible = shouldRenderByGroup && (icon.group == .alwaysVisible || fits)
            visibility[icon.id] = visible
            if visible { width = nextWidth }
        }

        icons = icons.map {
            var mutable = $0
            mutable.isVisible = visibility[$0.id] ?? false
            return mutable
        }
        persistConfiguration()
    }

    func updateIconGroup(id: String, group: VisibilityGroup) {
        guard let index = icons.firstIndex(where: { $0.id == id }) else { return }
        icons[index].group = group
        persistConfiguration()
    }

    func saveTodos() {
        taskStore.save(todos)
    }

    private func rank(_ group: VisibilityGroup) -> Int {
        switch group {
        case .alwaysVisible: return 3
        case .smartHide: return 2
        case .hidden: return 1
        }
    }

    private func loadConfiguration() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([MenuBarIcon].self, from: data)
        else { return }
        icons = decoded
    }

    private func persistConfiguration() {
        guard let data = try? JSONEncoder().encode(icons) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

private final class TaskStore {
    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MacMenubar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tasks.json")
    }

    func load() -> [TodoItem] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ todos: [TodoItem]) {
        guard let data = try? JSONEncoder().encode(todos) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
