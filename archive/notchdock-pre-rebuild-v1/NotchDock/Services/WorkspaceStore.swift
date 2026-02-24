import Foundation

final class WorkspaceStore: WorkspaceStoring {
    private let fileManager: FileManager
    private let stateURL: URL

    init(fileManager: FileManager = .default, stateURL: URL? = nil) {
        self.fileManager = fileManager
        if let stateURL {
            self.stateURL = stateURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.stateURL = appSupport
                .appendingPathComponent("NotchDock", isDirectory: true)
                .appendingPathComponent("workspace.json")
        }
        ensureDirectory()
    }

    func load() -> WorkspaceState {
        ensureDirectory()
        guard let data = try? Data(contentsOf: stateURL) else {
            return .empty
        }
        guard let state = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(_ state: WorkspaceState) throws {
        ensureDirectory()
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func ensureDirectory() {
        let directory = stateURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
