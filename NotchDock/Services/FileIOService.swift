import Foundation

final class FileIOService: @unchecked Sendable {
    let fileManager: FileManager
    let outputRoot: URL
    let workbenchRoot: URL

    init(fileManager: FileManager = .default, outputRoot: URL? = nil) {
        self.fileManager = fileManager
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.outputRoot = outputRoot ?? downloads.appendingPathComponent("NotchDock", isDirectory: true)
        self.workbenchRoot = downloads.appendingPathComponent("NotchDock/Workbench", isDirectory: true)
    }

    func datedOutputFolder(now: Date = .now) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let folder = outputRoot.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func ensureWorkbenchFolder() throws -> URL {
        try fileManager.createDirectory(at: workbenchRoot, withIntermediateDirectories: true)
        return workbenchRoot
    }

    func uniqueFileURL(in directory: URL, stem: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    func uniqueDirectoryURL(in directory: URL, stem: String) -> URL {
        var candidate = directory.appendingPathComponent(stem, isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    func fileSize(at url: URL) -> Int64 {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return directorySize(at: url)
        }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    func totalFileSize(urls: [URL]) -> Int64 {
        urls.reduce(into: Int64(0)) { partial, url in
            partial += fileSize(at: url)
        }
    }

    func moveToTrash(_ urls: [URL], generatedOutputs: [URL], undoWindow: TimeInterval) throws -> UndoToken {
        var sources: [URL] = []
        var trashed: [URL] = []
        for source in urls {
            var targetURL: NSURL?
            try fileManager.trashItem(at: source, resultingItemURL: &targetURL)
            sources.append(source)
            trashed.append((targetURL as URL?) ?? source)
        }
        return UndoToken(
            operationID: UUID().uuidString,
            sourceURLs: sources,
            trashedURLs: trashed,
            generatedURLs: generatedOutputs,
            expiresAt: Date().addingTimeInterval(undoWindow)
        )
    }

    func undo(_ token: UndoToken) -> Bool {
        guard Date() <= token.expiresAt else { return false }
        for (source, trashed) in zip(token.sourceURLs, token.trashedURLs) {
            guard fileManager.fileExists(atPath: trashed.path) else { return false }
            do {
                try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.removeItem(at: source)
                }
                try fileManager.moveItem(at: trashed, to: source)
            } catch {
                return false
            }
        }
        for output in token.generatedURLs where fileManager.fileExists(atPath: output.path) {
            try? fileManager.removeItem(at: output)
        }
        return true
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
