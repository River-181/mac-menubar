import Foundation

protocol OfficeConverting: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func convertToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL]
}

final class LibreOfficeConverter: OfficeConverting, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isAvailable: Bool {
        resolveExecutable() != nil
    }

    var unavailableReason: String? {
        isAvailable ? nil : "Install LibreOffice to enable Office -> PDF"
    }

    func convertToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        guard let executable = resolveExecutable() else {
            throw WorkActionError.operationFailed(unavailableReason ?? "LibreOffice is unavailable.")
        }

        var outputs: [URL] = []
        for input in inputs {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("NotchDockOffice-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "--headless",
                "--convert-to",
                "pdf",
                "--outdir",
                tempDir.path,
                input.path
            ]

            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw WorkActionError.operationFailed(message?.isEmpty == false ? message! : "LibreOffice conversion failed.")
            }

            let converted = tempDir
                .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("pdf")
            guard fileManager.fileExists(atPath: converted.path) else {
                throw WorkActionError.operationFailed("LibreOffice did not produce a PDF.")
            }

            let target = io.uniqueFileURL(
                in: outputDir,
                stem: "\(input.deletingPathExtension().lastPathComponent)__\(WorkActionKind.officeToPDF.rawValue)__v1",
                ext: "pdf"
            )
            try fileManager.moveItem(at: converted, to: target)
            outputs.append(target)
        }
        return outputs
    }

    private func resolveExecutable() -> URL? {
        let bundled = URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice")
        if fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["soffice"]
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty, fileManager.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
