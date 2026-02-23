import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

final class FileActionService: FileActionExecuting {
    private let fileManager: FileManager
    private let workbenchStore: WorkbenchStoring
    private let trashUndoWindow: TimeInterval

    init(
        fileManager: FileManager = .default,
        workbenchStore: WorkbenchStoring = WorkbenchStore(),
        trashUndoWindow: TimeInterval = 8
    ) {
        self.fileManager = fileManager
        self.workbenchStore = workbenchStore
        self.trashUndoWindow = trashUndoWindow
    }

    func classify(urls: [URL]) -> DropClassification {
        let descriptors = urls
            .map { descriptor(for: $0) }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }

        guard !descriptors.isEmpty else {
            return DropClassification(kind: .unsupported, descriptors: [], recommendedAction: nil, secondaryActions: [])
        }

        let types = descriptors.map { UTType($0.utType) ?? .data }
        let hasImages = types.contains { $0.conforms(to: .image) }
        let hasPDFs = types.contains { $0.conforms(to: .pdf) }
        let hasZIPs = descriptors.contains { descriptor in
            let type = UTType(descriptor.utType) ?? .data
            return type.conforms(to: .zip) || descriptor.url.pathExtension.lowercased() == "zip"
        }
        let hasOther = descriptors.contains { descriptor in
            let type = UTType(descriptor.utType) ?? .data
            let isZip = type.conforms(to: .zip) || descriptor.url.pathExtension.lowercased() == "zip"
            return !type.conforms(to: .image) && !type.conforms(to: .pdf) && !isZip
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
        let recommendedAction: NotchActionKind?
        switch kind {
        case .images:
            recommendedAction = .optimizeImages
        case .pdfs:
            recommendedAction = .optimizePDFKeepText
        case .zipArchives:
            recommendedAction = .extractZip
        case .mixed:
            recommendedAction = .compressZip
        case .unsupported:
            recommendedAction = .sendToWorkbench
        }

        let secondary = actions.filter { $0 != recommendedAction }
        return DropClassification(
            kind: kind,
            descriptors: descriptors,
            recommendedAction: recommendedAction,
            secondaryActions: secondary
        )
    }

    func availableActions(for kind: DropContentKind) -> [NotchActionKind] {
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

    func execute(action: NotchActionKind, inputs: [DroppedFileDescriptor], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult {
        guard !inputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        switch action {
        case .imageToPDF:
            let output = try convertImagesToPDF(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: [output],
                message: "Created PDF: \(output.lastPathComponent)",
                undoToken: nil,
                spaceDeltaBytes: 0,
                warnings: []
            )

        case .pdfToImages:
            let outputs = try convertPDFsToImages(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                message: "Exported \(outputs.count) image file(s)",
                undoToken: nil,
                spaceDeltaBytes: 0,
                warnings: []
            )

        case .compressZip:
            let beforeBytes = totalFileSize(urls: inputs.map(\.url))
            let output = try compressToZip(inputs)
            let zipBytes = fileSize(at: output)
            let delta = max(0, beforeBytes - zipBytes)

            let replacements = inputs.map {
                UndoReplacement(sourceURL: $0.url, generatedURL: output)
            }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .compressAndTrashOriginals,
                replacements: replacements
            )

            return ActionExecutionResult(
                action: action,
                outputs: [output],
                message: "Created archive: \(output.lastPathComponent) · estimated reclaim \(byteString(delta))",
                undoToken: undoToken,
                spaceDeltaBytes: delta,
                warnings: []
            )

        case .extractZip:
            let outputs = try extractZIPArchives(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                message: "Extracted \(outputs.count) archive(s)",
                undoToken: nil,
                spaceDeltaBytes: 0,
                warnings: []
            )

        case .optimizeImages:
            let optimized = try optimizeImages(inputs)
            let beforeBytes = totalFileSize(urls: inputs.map(\.url))
            let afterBytes = totalFileSize(urls: optimized)
            let delta = max(0, beforeBytes - afterBytes)

            let replacements = zip(inputs.map(\.url), optimized).map { source, generated in
                UndoReplacement(sourceURL: source, generatedURL: generated)
            }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )

            return ActionExecutionResult(
                action: action,
                outputs: optimized,
                message: "Optimized \(optimized.count) image(s) · reclaimed \(byteString(delta))",
                undoToken: undoToken,
                spaceDeltaBytes: delta,
                warnings: []
            )

        case .optimizePDFKeepText:
            let optimized = try optimizePDFKeepText(inputs)
            let beforeBytes = totalFileSize(urls: inputs.map(\.url))
            let afterBytes = totalFileSize(urls: optimized)
            let delta = max(0, beforeBytes - afterBytes)

            let replacements = zip(inputs.map(\.url), optimized).map { source, generated in
                UndoReplacement(sourceURL: source, generatedURL: generated)
            }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )

            return ActionExecutionResult(
                action: action,
                outputs: optimized,
                message: "Optimized \(optimized.count) PDF(s), text preserved · reclaimed \(byteString(delta))",
                undoToken: undoToken,
                spaceDeltaBytes: delta,
                warnings: []
            )

        case .resizeImages:
            let resized = try resizeImages(inputs)
            let beforeBytes = totalFileSize(urls: inputs.map(\.url))
            let afterBytes = totalFileSize(urls: resized)
            let delta = max(0, beforeBytes - afterBytes)

            let replacements = zip(inputs.map(\.url), resized).map { source, generated in
                UndoReplacement(sourceURL: source, generatedURL: generated)
            }
            let undoToken = try moveToTrash(
                inputs,
                operationKind: .replaceWithOptimized,
                replacements: replacements
            )

            return ActionExecutionResult(
                action: action,
                outputs: resized,
                message: "Resized \(resized.count) image(s) · reclaimed \(byteString(delta))",
                undoToken: undoToken,
                spaceDeltaBytes: delta,
                warnings: []
            )

        case .sendToWorkbench:
            let outputs = try workbenchStore.store(urls: inputs.map(\.url))
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                message: "Moved to Workbench: \(outputs.count) file(s)",
                undoToken: nil,
                spaceDeltaBytes: 0,
                warnings: []
            )

        case .moveToTrash:
            let token = try moveToTrash(inputs, operationKind: .moveToTrash, replacements: [])
            return ActionExecutionResult(
                action: action,
                outputs: token.destinationURLs,
                message: "Moved to Trash: \(token.destinationURLs.count) file(s)",
                undoToken: token,
                spaceDeltaBytes: 0,
                warnings: []
            )
        }
    }

    func undo(token: UndoToken) -> Bool {
        guard Date() <= token.expiresAt else {
            return false
        }

        let pairs = Array(zip(token.sourceURLs, token.destinationURLs))
        for (source, destination) in pairs {
            guard fileManager.fileExists(atPath: destination.path) else {
                return false
            }
            do {
                let parent = source.deletingLastPathComponent()
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
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
            do {
                try fileManager.removeItem(at: output)
            } catch {
                return false
            }
        }

        return true
    }

    func workbenchFolderURL() -> URL {
        workbenchStore.folderURL
    }

    private func descriptor(for url: URL) -> DroppedFileDescriptor {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let fileSize = Int64(values?.fileSize ?? 0)

        return DroppedFileDescriptor(
            id: url.path,
            url: url,
            utType: contentType.identifier,
            fileName: url.lastPathComponent,
            fileSize: fileSize
        )
    }

    private func convertImagesToPDF(_ inputs: [DroppedFileDescriptor]) throws -> URL {
        let imageInputs = inputs.filter {
            (UTType($0.utType) ?? .data).conforms(to: .image)
        }
        guard !imageInputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        let document = PDFDocument()
        var pageIndex = 0

        for input in imageInputs {
            guard let image = NSImage(contentsOf: input.url) else {
                throw FileActionError.failedToReadImage(input.url)
            }
            guard let page = PDFPage(image: image) else {
                throw FileActionError.failedToReadImage(input.url)
            }
            document.insert(page, at: pageIndex)
            pageIndex += 1
        }

        let outputDirectory = imageInputs[0].url.deletingLastPathComponent()
        let baseName = imageInputs.count == 1
            ? imageInputs[0].url.deletingPathExtension().lastPathComponent
            : "images"
        let outputURL = uniqueFileURL(in: outputDirectory, stem: baseName, ext: "pdf")

        guard document.write(to: outputURL) else {
            throw FileActionError.failedToWriteOutput(outputURL)
        }

        return outputURL
    }

    private func convertPDFsToImages(_ inputs: [DroppedFileDescriptor]) throws -> [URL] {
        let pdfInputs = inputs.filter {
            (UTType($0.utType) ?? .data).conforms(to: .pdf)
        }
        guard !pdfInputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for input in pdfInputs {
            guard let document = PDFDocument(url: input.url) else {
                throw FileActionError.failedToReadPDF(input.url)
            }

            let stem = input.url.deletingPathExtension().lastPathComponent
            let directory = input.url.deletingLastPathComponent()

            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let outputURL = uniqueFileURL(in: directory, stem: "\(stem)-page-\(index + 1)", ext: "png")
                let pngData = try renderPDFPageToPNG(page: page)
                do {
                    try pngData.write(to: outputURL, options: .atomic)
                } catch {
                    throw FileActionError.failedToWriteOutput(outputURL)
                }
                outputs.append(outputURL)
            }
        }

        return outputs
    }

    private func extractZIPArchives(_ inputs: [DroppedFileDescriptor]) throws -> [URL] {
        let archives = inputs.filter {
            let type = UTType($0.utType) ?? .data
            return type.conforms(to: .zip) || $0.url.pathExtension.lowercased() == "zip"
        }
        guard !archives.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for archive in archives {
            let parent = archive.url.deletingLastPathComponent()
            let stem = archive.url.deletingPathExtension().lastPathComponent
            let outputDirectory = uniqueDirectoryURL(in: parent, stem: stem)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try runDittoDecompression(source: archive.url, destination: outputDirectory)
            outputs.append(outputDirectory)
        }

        return outputs
    }

    private func optimizeImages(_ inputs: [DroppedFileDescriptor]) throws -> [URL] {
        let imageInputs = inputs.filter {
            (UTType($0.utType) ?? .data).conforms(to: .image)
        }
        guard !imageInputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for input in imageInputs {
            guard let image = NSImage(contentsOf: input.url), let bitmap = bitmapRep(from: image) else {
                throw FileActionError.failedToReadImage(input.url)
            }

            let hasAlpha = bitmapHasAlpha(bitmap)
            let parent = input.url.deletingLastPathComponent()
            let stem = input.url.deletingPathExtension().lastPathComponent + "-optimized"
            let ext = hasAlpha ? "png" : "jpg"
            let outputURL = uniqueFileURL(in: parent, stem: stem, ext: ext)

            let properties: [NSBitmapImageRep.PropertyKey: Any] = hasAlpha
                ? [.compressionFactor: 0.82]
                : [.compressionFactor: 0.72]

            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
            guard let data = bitmap.representation(using: type, properties: properties) else {
                throw FileActionError.failedToWriteOutput(outputURL)
            }

            do {
                try data.write(to: outputURL, options: .atomic)
            } catch {
                throw FileActionError.failedToWriteOutput(outputURL)
            }

            outputs.append(outputURL)
        }

        return outputs
    }

    private func optimizePDFKeepText(_ inputs: [DroppedFileDescriptor]) throws -> [URL] {
        let pdfInputs = inputs.filter {
            (UTType($0.utType) ?? .data).conforms(to: .pdf)
        }
        guard !pdfInputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for input in pdfInputs {
            guard let document = PDFDocument(url: input.url) else {
                throw FileActionError.failedToReadPDF(input.url)
            }

            let directory = input.url.deletingLastPathComponent()
            let stem = input.url.deletingPathExtension().lastPathComponent + "-optimized"
            let outputURL = uniqueFileURL(in: directory, stem: stem, ext: "pdf")

            guard document.write(to: outputURL) else {
                throw FileActionError.failedToWriteOutput(outputURL)
            }

            outputs.append(outputURL)
        }

        return outputs
    }

    private func resizeImages(_ inputs: [DroppedFileDescriptor], maxLongEdge: CGFloat = 2048) throws -> [URL] {
        let imageInputs = inputs.filter {
            (UTType($0.utType) ?? .data).conforms(to: .image)
        }
        guard !imageInputs.isEmpty else {
            throw FileActionError.unsupportedInput
        }

        var outputs: [URL] = []
        for input in imageInputs {
            guard let image = NSImage(contentsOf: input.url), let resized = resizedImage(image, maxLongEdge: maxLongEdge), let bitmap = bitmapRep(from: resized) else {
                throw FileActionError.failedToReadImage(input.url)
            }

            let hasAlpha = bitmapHasAlpha(bitmap)
            let parent = input.url.deletingLastPathComponent()
            let stem = input.url.deletingPathExtension().lastPathComponent + "-resized"
            let ext = hasAlpha ? "png" : "jpg"
            let outputURL = uniqueFileURL(in: parent, stem: stem, ext: ext)

            let properties: [NSBitmapImageRep.PropertyKey: Any] = hasAlpha
                ? [.compressionFactor: 0.84]
                : [.compressionFactor: 0.78]
            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg

            guard let data = bitmap.representation(using: type, properties: properties) else {
                throw FileActionError.failedToWriteOutput(outputURL)
            }

            do {
                try data.write(to: outputURL, options: .atomic)
            } catch {
                throw FileActionError.failedToWriteOutput(outputURL)
            }

            outputs.append(outputURL)
        }

        return outputs
    }

    private func renderPDFPageToPNG(page: PDFPage) throws -> Data {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0

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
            throw FileActionError.commandFailed("Unable to allocate bitmap")
        }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw FileActionError.commandFailed("Unable to create graphics context")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        context.cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw FileActionError.commandFailed("Unable to encode PNG")
        }
        return data
    }

    private func compressToZip(_ inputs: [DroppedFileDescriptor]) throws -> URL {
        let urls = inputs.map(\.url)
        guard let first = urls.first else {
            throw FileActionError.unsupportedInput
        }

        let outputDirectory = first.deletingLastPathComponent()
        let stem = urls.count == 1
            ? first.deletingPathExtension().lastPathComponent
            : "compressed"
        let outputURL = uniqueFileURL(in: outputDirectory, stem: stem, ext: "zip")

        if urls.count == 1 {
            try runDittoCompression(source: first, destination: outputURL)
            return outputURL
        }

        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MacMenubar-zip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRoot)
        }

        for url in urls {
            let destination = temporaryRoot.appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: destination)
        }

        try runDittoCompression(source: temporaryRoot, destination: outputURL)
        return outputURL
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
            throw FileActionError.commandFailed(errorText ?? "ditto exit code \(process.terminationStatus)")
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
            throw FileActionError.commandFailed(errorText ?? "ditto exit code \(process.terminationStatus)")
        }
    }

    private func moveToTrash(
        _ inputs: [DroppedFileDescriptor],
        operationKind: DangerousOperationKind,
        replacements: [UndoReplacement]
    ) throws -> UndoToken {
        var sourceURLs: [URL] = []
        var trashedURLs: [URL] = []

        for input in inputs {
            var trashed: NSURL?
            do {
                try fileManager.trashItem(at: input.url, resultingItemURL: &trashed)
                sourceURLs.append(input.url)
                trashedURLs.append((trashed as URL?) ?? input.url)
            } catch {
                throw FileActionError.commandFailed("Failed to move \(input.fileName) to Trash")
            }
        }

        return UndoToken(
            operationKind: operationKind,
            sourceURLs: sourceURLs,
            destinationURLs: trashedURLs,
            replacements: replacements,
            expiresAt: Date().addingTimeInterval(trashUndoWindow)
        )
    }

    private func bitmapRep(from image: NSImage) -> NSBitmapImageRep? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSBitmapImageRep(cgImage: cg)
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private func bitmapHasAlpha(_ bitmap: NSBitmapImageRep) -> Bool {
        bitmap.hasAlpha
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
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(stem)_\(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private func uniqueDirectoryURL(in directory: URL, stem: String) -> URL {
        var candidate = directory.appendingPathComponent(stem, isDirectory: true)
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)_\(counter)", isDirectory: true)
            counter += 1
        }
        return candidate
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
