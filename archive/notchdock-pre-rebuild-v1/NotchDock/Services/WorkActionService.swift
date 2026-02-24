import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum WorkActionError: Error, LocalizedError {
    case unsupportedInput
    case failedToReadImage(URL)
    case failedToReadPDF(URL)
    case failedToWriteOutput(URL)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "Unsupported input selection."
        case .failedToReadImage(let url):
            return "Failed to read image: \(url.lastPathComponent)."
        case .failedToReadPDF(let url):
            return "Failed to read PDF: \(url.lastPathComponent)."
        case .failedToWriteOutput(let url):
            return "Failed to write output: \(url.lastPathComponent)."
        case .commandFailed(let reason):
            return "Command failed: \(reason)."
        }
    }
}

final class WorkActionService: WorkActionExecuting {
    private let fileManager: FileManager
    private let workbenchStore: WorkbenchFileStoring
    private let outputRootURL: URL
    private let trashUndoWindow: TimeInterval

    init(
        fileManager: FileManager = .default,
        workbenchStore: WorkbenchFileStoring = WorkbenchStore(),
        outputRootURL: URL? = nil,
        trashUndoWindow: TimeInterval = 8
    ) {
        self.fileManager = fileManager
        self.workbenchStore = workbenchStore
        if let outputRootURL {
            self.outputRootURL = outputRootURL
        } else {
            let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.outputRootURL = downloads.appendingPathComponent("NotchDock", isDirectory: true)
        }
        self.trashUndoWindow = trashUndoWindow
    }

    func classify(_ urls: [URL]) -> DropPlan {
        guard !urls.isEmpty else {
            return DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
        }

        let types = urls.map { detectedType(for: $0) }
        let hasImages = types.contains { $0.conforms(to: .image) }
        let hasPDFs = types.contains { $0.conforms(to: .pdf) }
        let hasZIPs = urls.contains { isZIP($0) }
        let hasOther = zip(urls, types).contains { url, type in
            !type.conforms(to: .image) && !type.conforms(to: .pdf) && !isZIP(url)
        }

        let kind: DropContentKind
        if hasImages && !hasPDFs && !hasZIPs && !hasOther {
            kind = .images
        } else if hasPDFs && !hasImages && !hasZIPs && !hasOther {
            kind = .pdfs
        } else if hasZIPs && !hasImages && !hasPDFs && !hasOther {
            kind = .zipArchives
        } else if hasImages || hasPDFs || hasZIPs {
            kind = .mixed
        } else {
            kind = .unsupported
        }

        let actions = availableActions(for: kind)
        let recommended: WorkActionKind?
        switch kind {
        case .images:
            recommended = .optimizeImages
        case .pdfs:
            recommended = .optimizePDFKeepText
        case .zipArchives:
            recommended = .extractZip
        case .mixed:
            recommended = .compressZip
        case .unsupported:
            recommended = .sendToWorkbench
        }

        return DropPlan(kind: kind, recommendedAction: recommended, secondaryActions: actions.filter { $0 != recommended })
    }

    func execute(action: WorkActionKind, inputs: [URL], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult {
        guard !inputs.isEmpty else {
            throw WorkActionError.unsupportedInput
        }

        let outputDirectory = try resolveOutputDirectory(for: outputPolicy)
        switch action {
        case .imageToPDF:
            let output = try convertImagesToPDF(inputs, outputDirectory: outputDirectory)
            return ActionExecutionResult(
                action: action,
                outputs: [output],
                reclaimedBytes: 0,
                message: "Created PDF: \(output.lastPathComponent)",
                undoToken: nil,
                warnings: []
            )

        case .pdfToImages:
            let outputs = try convertPDFsToImages(inputs, outputDirectory: outputDirectory)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                reclaimedBytes: 0,
                message: "Exported \(outputs.count) image file(s)",
                undoToken: nil,
                warnings: []
            )

        case .compressZip:
            let beforeBytes = totalFileSize(urls: inputs)
            let output = try compressToZip(inputs, outputDirectory: outputDirectory)
            let zipBytes = fileSize(at: output)
            let reclaimedBytes = max(0, beforeBytes - zipBytes)
            let replacements = inputs.map { UndoReplacement(sourceURL: $0, generatedURL: output) }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .compressAndTrashOriginals,
                replacements: replacements
            )
            return ActionExecutionResult(
                action: action,
                outputs: [output],
                reclaimedBytes: reclaimedBytes,
                message: "Created archive \(output.lastPathComponent) · reclaimed \(byteString(reclaimedBytes))",
                undoToken: undoToken,
                warnings: []
            )

        case .extractZip:
            let outputs = try extractZIPArchives(inputs, outputDirectory: outputDirectory)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                reclaimedBytes: 0,
                message: "Extracted \(outputs.count) archive(s)",
                undoToken: nil,
                warnings: []
            )

        case .optimizeImages:
            let optimized = try optimizeImages(inputs, outputDirectory: outputDirectory)
            let beforeBytes = totalFileSize(urls: inputs)
            let afterBytes = totalFileSize(urls: optimized)
            let reclaimedBytes = max(0, beforeBytes - afterBytes)
            let replacements = zip(inputs, optimized).map { UndoReplacement(sourceURL: $0.0, generatedURL: $0.1) }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )
            return ActionExecutionResult(
                action: action,
                outputs: optimized,
                reclaimedBytes: reclaimedBytes,
                message: "Optimized \(optimized.count) image(s) · reclaimed \(byteString(reclaimedBytes))",
                undoToken: undoToken,
                warnings: []
            )

        case .optimizePDFKeepText:
            let optimized = try optimizePDFKeepText(inputs, outputDirectory: outputDirectory)
            let beforeBytes = totalFileSize(urls: inputs)
            let afterBytes = totalFileSize(urls: optimized)
            let reclaimedBytes = max(0, beforeBytes - afterBytes)
            let replacements = zip(inputs, optimized).map { UndoReplacement(sourceURL: $0.0, generatedURL: $0.1) }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )
            return ActionExecutionResult(
                action: action,
                outputs: optimized,
                reclaimedBytes: reclaimedBytes,
                message: "Optimized \(optimized.count) PDF(s) · reclaimed \(byteString(reclaimedBytes))",
                undoToken: undoToken,
                warnings: []
            )

        case .resizeImages:
            let resized = try resizeImages(inputs, outputDirectory: outputDirectory)
            let beforeBytes = totalFileSize(urls: inputs)
            let afterBytes = totalFileSize(urls: resized)
            let reclaimedBytes = max(0, beforeBytes - afterBytes)
            let replacements = zip(inputs, resized).map { UndoReplacement(sourceURL: $0.0, generatedURL: $0.1) }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )
            return ActionExecutionResult(
                action: action,
                outputs: resized,
                reclaimedBytes: reclaimedBytes,
                message: "Resized \(resized.count) image(s) · reclaimed \(byteString(reclaimedBytes))",
                undoToken: undoToken,
                warnings: []
            )

        case .sendToWorkbench:
            let outputs = try workbenchStore.store(urls: inputs)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                reclaimedBytes: 0,
                message: "Moved to Workbench: \(outputs.count) file(s)",
                undoToken: nil,
                warnings: []
            )

        case .moveToTrash:
            let token = try moveToTrash(inputs, operationKind: .moveToTrash, replacements: [])
            return ActionExecutionResult(
                action: action,
                outputs: token.destinationURLs,
                reclaimedBytes: 0,
                message: "Moved to Trash: \(token.destinationURLs.count) file(s)",
                undoToken: token,
                warnings: []
            )
        }
    }

    func undo(token: UndoToken) -> Bool {
        guard Date() <= token.expiresAt else {
            return false
        }

        for (source, destination) in zip(token.sourceURLs, token.destinationURLs) {
            guard fileManager.fileExists(atPath: destination.path) else {
                return false
            }
            do {
                try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.removeItem(at: source)
                }
                try fileManager.moveItem(at: destination, to: source)
            } catch {
                return false
            }
        }

        let generated = Set(token.replacements.map(\.generatedURL))
        for output in generated where fileManager.fileExists(atPath: output.path) {
            try? fileManager.removeItem(at: output)
        }
        return true
    }

    func availableActions(for kind: DropContentKind) -> [WorkActionKind] {
        switch kind {
        case .images:
            return [.optimizeImages, .resizeImages, .imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash]
        case .pdfs:
            return [.optimizePDFKeepText, .pdfToImages, .compressZip, .sendToWorkbench, .moveToTrash]
        case .zipArchives:
            return [.extractZip, .compressZip, .sendToWorkbench, .moveToTrash]
        case .mixed:
            return [.compressZip, .sendToWorkbench, .moveToTrash]
        case .unsupported:
            return [.sendToWorkbench, .compressZip, .moveToTrash]
        }
    }

    private func resolveOutputDirectory(for policy: FileOutputPolicy) throws -> URL {
        switch policy {
        case .datedFolder:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dated = outputRootURL.appendingPathComponent(formatter.string(from: .now), isDirectory: true)
            try fileManager.createDirectory(at: dated, withIntermediateDirectories: true)
            return dated
        }
    }

    private func convertImagesToPDF(_ inputs: [URL], outputDirectory: URL) throws -> URL {
        let images = inputs.filter { detectedType(for: $0).conforms(to: .image) }
        guard !images.isEmpty else {
            throw WorkActionError.unsupportedInput
        }
        let document = PDFDocument()
        var index = 0
        for imageURL in images {
            guard let image = NSImage(contentsOf: imageURL), let page = PDFPage(image: image) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }
            document.insert(page, at: index)
            index += 1
        }
        let output = uniqueFileURL(in: outputDirectory, stem: actionStem(for: images.first!, action: .imageToPDF), ext: "pdf")
        guard document.write(to: output) else {
            throw WorkActionError.failedToWriteOutput(output)
        }
        return output
    }

    private func convertPDFsToImages(_ inputs: [URL], outputDirectory: URL) throws -> [URL] {
        let pdfs = inputs.filter { detectedType(for: $0).conforms(to: .pdf) }
        guard !pdfs.isEmpty else {
            throw WorkActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for pdfURL in pdfs {
            guard let document = PDFDocument(url: pdfURL) else {
                throw WorkActionError.failedToReadPDF(pdfURL)
            }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                let output = uniqueFileURL(
                    in: outputDirectory,
                    stem: "\(actionStem(for: pdfURL, action: .pdfToImages))-p\(pageIndex + 1)",
                    ext: "png"
                )
                let data = try renderPDFPageToPNG(page: page)
                try data.write(to: output, options: .atomic)
                outputs.append(output)
            }
        }
        return outputs
    }

    private func compressToZip(_ inputs: [URL], outputDirectory: URL) throws -> URL {
        let stemBase: URL = inputs.count == 1 ? inputs[0] : URL(fileURLWithPath: "batch")
        let output = uniqueFileURL(in: outputDirectory, stem: actionStem(for: stemBase, action: .compressZip), ext: "zip")

        if inputs.count == 1 {
            try runDittoCompression(source: inputs[0], destination: output)
            return output
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NotchDock-zip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        for input in inputs {
            try fileManager.copyItem(at: input, to: tempRoot.appendingPathComponent(input.lastPathComponent))
        }
        try runDittoCompression(source: tempRoot, destination: output)
        return output
    }

    private func extractZIPArchives(_ inputs: [URL], outputDirectory: URL) throws -> [URL] {
        let archives = inputs.filter { isZIP($0) }
        guard !archives.isEmpty else {
            throw WorkActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for archive in archives {
            let destination = uniqueDirectoryURL(in: outputDirectory, stem: actionStem(for: archive, action: .extractZip))
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try runDittoDecompression(source: archive, destination: destination)
            outputs.append(destination)
        }
        return outputs
    }

    private func optimizeImages(_ inputs: [URL], outputDirectory: URL) throws -> [URL] {
        let imageInputs = inputs.filter { detectedType(for: $0).conforms(to: .image) }
        guard !imageInputs.isEmpty else {
            throw WorkActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for input in imageInputs {
            guard let image = NSImage(contentsOf: input), let bitmap = bitmapRep(from: image) else {
                throw WorkActionError.failedToReadImage(input)
            }

            let hasAlpha = bitmap.hasAlpha
            let ext = hasAlpha ? "png" : "jpg"
            let output = uniqueFileURL(in: outputDirectory, stem: actionStem(for: input, action: .optimizeImages), ext: ext)
            let props: [NSBitmapImageRep.PropertyKey: Any] = hasAlpha ? [.compressionFactor: 0.82] : [.compressionFactor: 0.72]
            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
            guard let data = bitmap.representation(using: type, properties: props) else {
                throw WorkActionError.failedToWriteOutput(output)
            }
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    private func optimizePDFKeepText(_ inputs: [URL], outputDirectory: URL) throws -> [URL] {
        let pdfInputs = inputs.filter { detectedType(for: $0).conforms(to: .pdf) }
        guard !pdfInputs.isEmpty else {
            throw WorkActionError.unsupportedInput
        }
        var outputs: [URL] = []
        for input in pdfInputs {
            guard let document = PDFDocument(url: input) else {
                throw WorkActionError.failedToReadPDF(input)
            }
            let output = uniqueFileURL(in: outputDirectory, stem: actionStem(for: input, action: .optimizePDFKeepText), ext: "pdf")
            guard document.write(to: output) else {
                throw WorkActionError.failedToWriteOutput(output)
            }
            outputs.append(output)
        }
        return outputs
    }

    private func resizeImages(_ inputs: [URL], outputDirectory: URL, maxLongEdge: CGFloat = 2048) throws -> [URL] {
        let imageInputs = inputs.filter { detectedType(for: $0).conforms(to: .image) }
        guard !imageInputs.isEmpty else {
            throw WorkActionError.unsupportedInput
        }
        var outputs: [URL] = []
        for input in imageInputs {
            guard let image = NSImage(contentsOf: input), let resized = resizedImage(image, maxLongEdge: maxLongEdge), let bitmap = bitmapRep(from: resized) else {
                throw WorkActionError.failedToReadImage(input)
            }
            let hasAlpha = bitmap.hasAlpha
            let ext = hasAlpha ? "png" : "jpg"
            let output = uniqueFileURL(in: outputDirectory, stem: actionStem(for: input, action: .resizeImages), ext: ext)
            let props: [NSBitmapImageRep.PropertyKey: Any] = hasAlpha ? [.compressionFactor: 0.84] : [.compressionFactor: 0.78]
            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
            guard let data = bitmap.representation(using: type, properties: props) else {
                throw WorkActionError.failedToWriteOutput(output)
            }
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    private func moveToTrash(_ inputs: [URL], operationKind: DangerousOperationKind, replacements: [UndoReplacement]) throws -> UndoToken {
        var sourceURLs: [URL] = []
        var trashedURLs: [URL] = []
        for input in inputs {
            var trashed: NSURL?
            do {
                try fileManager.trashItem(at: input, resultingItemURL: &trashed)
            } catch {
                throw WorkActionError.commandFailed("Failed to move \(input.lastPathComponent) to Trash")
            }
            sourceURLs.append(input)
            trashedURLs.append((trashed as URL?) ?? input)
        }

        return UndoToken(
            operationID: UUID().uuidString,
            operationKind: operationKind,
            sourceURLs: sourceURLs,
            destinationURLs: trashedURLs,
            replacements: replacements,
            createdAt: .now,
            expiresAt: Date().addingTimeInterval(trashUndoWindow)
        )
    }

    private func detectedType(for url: URL) -> UTType {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
    }

    private func isZIP(_ url: URL) -> Bool {
        let type = detectedType(for: url)
        return type.conforms(to: .zip) || url.pathExtension.lowercased() == "zip"
    }

    private func actionStem(for source: URL, action: WorkActionKind) -> String {
        let base = source.deletingPathExtension().lastPathComponent.isEmpty ? "file" : source.deletingPathExtension().lastPathComponent
        return "\(base)__\(action.rawValue)__v1"
    }

    private func renderPDFPageToPNG(page: PDFPage) throws -> Data {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let pixelWidth = max(1, Int((pageRect.width * scale).rounded()))
        let pixelHeight = max(1, Int((pageRect.height * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw WorkActionError.commandFailed("Unable to allocate bitmap")
        }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw WorkActionError.commandFailed("Unable to create graphics context")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        context.cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw WorkActionError.commandFailed("Unable to encode PNG")
        }
        return data
    }

    private func bitmapRep(from image: NSImage) -> NSBitmapImageRep? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSBitmapImageRep(cgImage: cg)
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private func resizedImage(_ image: NSImage, maxLongEdge: CGFloat) -> NSImage? {
        let original = image.size
        let longEdge = max(original.width, original.height)
        guard longEdge > 0 else { return nil }

        let scale = min(1.0, maxLongEdge / longEdge)
        let newSize = NSSize(width: floor(original.width * scale), height: floor(original.height * scale))
        guard newSize.width > 0, newSize.height > 0 else { return nil }

        let canvas = NSImage(size: newSize)
        canvas.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: original), operation: .copy, fraction: 1.0)
        canvas.unlockFocus()
        return canvas
    }

    private func runDittoCompression(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkActionError.commandFailed(errorText ?? "ditto exit code \(process.terminationStatus)")
        }
    }

    private func runDittoDecompression(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, destination.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WorkActionError.commandFailed(errorText ?? "ditto exit code \(process.terminationStatus)")
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]), values.isDirectory == true {
            return directorySize(at: url)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
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

    private func totalFileSize(urls: [URL]) -> Int64 {
        urls.reduce(into: Int64(0)) { partial, url in
            partial += fileSize(at: url)
        }
    }

    private func uniqueFileURL(in directory: URL, stem: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(stem)-\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private func uniqueDirectoryURL(in directory: URL, stem: String) -> URL {
        var candidate = directory.appendingPathComponent(stem, isDirectory: true)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(counter)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
