import Foundation

final class WorkbenchStore: WorkbenchStoring {
    let folderURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        folderURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let folderURL {
            self.folderURL = folderURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.folderURL = appSupport
                .appendingPathComponent("MacMenubar", isDirectory: true)
                .appendingPathComponent("Workbench", isDirectory: true)
        }
        ensureDirectory()
    }

    func store(urls: [URL]) throws -> [URL] {
        ensureDirectory()
        var outputs: [URL] = []

        for url in urls {
            let destination = uniqueDestination(for: url.lastPathComponent)
            try fileManager.copyItem(at: url, to: destination)
            outputs.append(destination)
        }

        return outputs
    }

    func list() -> [URL] {
        ensureDirectory()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return lDate > rDate
        }
    }

    func clear() throws {
        ensureDirectory()
        let entries = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        for entry in entries {
            try fileManager.removeItem(at: entry)
        }
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }

    private func uniqueDestination(for lastPathComponent: String) -> URL {
        let baseURL = folderURL.appendingPathComponent(lastPathComponent)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let ext = baseURL.pathExtension
        let stem = ext.isEmpty ? baseURL.lastPathComponent : String(baseURL.lastPathComponent.dropLast(ext.count + 1))

        var counter = 1
        while true {
            let candidateName = "\(stem)_\(counter)"
            let candidate = ext.isEmpty
                ? folderURL.appendingPathComponent(candidateName)
                : folderURL.appendingPathComponent(candidateName).appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
