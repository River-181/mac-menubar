import Foundation

protocol WorkbenchFileStoring: AnyObject {
    func store(urls: [URL]) throws -> [URL]
    func folderURL() -> URL
}

final class WorkbenchStore: WorkbenchFileStoring {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.rootURL = downloads
                .appendingPathComponent("NotchDock", isDirectory: true)
                .appendingPathComponent("Workbench", isDirectory: true)
        }
        ensureDirectory()
    }

    func store(urls: [URL]) throws -> [URL] {
        ensureDirectory()
        var outputs: [URL] = []
        for source in urls {
            let destination = uniqueDestination(for: source.lastPathComponent)
            try fileManager.copyItem(at: source, to: destination)
            outputs.append(destination)
        }
        return outputs
    }

    func folderURL() -> URL {
        ensureDirectory()
        return rootURL
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let base = rootURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: base.path) else { return base }

        let ext = base.pathExtension
        let stem = ext.isEmpty ? base.lastPathComponent : String(base.lastPathComponent.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidateStem = "\(stem)-\(counter)"
            let candidate = ext.isEmpty
                ? rootURL.appendingPathComponent(candidateStem)
                : rootURL.appendingPathComponent(candidateStem).appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
