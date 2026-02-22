import AppKit
import Foundation
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
            return DropClassification(kind: .unsupported, descriptors: [], defaultAction: nil)
        }

        let types = descriptors.map { UTType($0.utType) ?? .data }
        let hasImages = types.contains { $0.conforms(to: .image) }
        let hasPDFs = types.contains { $0.conforms(to: .pdf) }
        let hasOther = types.contains { !$0.conforms(to: .image) && !$0.conforms(to: .pdf) }

        let kind: DropContentKind
        if hasImages && !hasPDFs && !hasOther {
            kind = .images
        } else if hasPDFs && !hasImages && !hasOther {
            kind = .pdfs
        } else if hasImages || hasPDFs {
            kind = .mixed
        } else {
            kind = .unsupported
        }

        let defaultAction: NotchActionKind?
        switch kind {
        case .images:
            defaultAction = .imageToPDF
        case .pdfs:
            defaultAction = .pdfToImages
        case .mixed:
            defaultAction = .compressZip
        case .unsupported:
            defaultAction = .sendToWorkbench
        }

        return DropClassification(kind: kind, descriptors: descriptors, defaultAction: defaultAction)
    }

    func availableActions(for kind: DropContentKind) -> [NotchActionKind] {
        switch kind {
        case .images:
            return [.imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash]
        case .pdfs:
            return [.pdfToImages, .compressZip, .sendToWorkbench, .moveToTrash]
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
                undoToken: nil
            )

        case .pdfToImages:
            let outputs = try convertPDFsToImages(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                message: "Exported \(outputs.count) image file(s)",
                undoToken: nil
            )

        case .compressZip:
            let output = try compressToZip(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: [output],
                message: "Created archive: \(output.lastPathComponent)",
                undoToken: nil
            )

        case .sendToWorkbench:
            let outputs = try workbenchStore.store(urls: inputs.map(\.url))
            return ActionExecutionResult(
                action: action,
                outputs: outputs,
                message: "Moved to Workbench: \(outputs.count) file(s)",
                undoToken: nil
            )

        case .moveToTrash:
            let token = try moveToTrash(inputs)
            return ActionExecutionResult(
                action: action,
                outputs: token.destinationURLs,
                message: "Moved to Trash: \(token.destinationURLs.count) file(s)",
                undoToken: token
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

    private func moveToTrash(_ inputs: [DroppedFileDescriptor]) throws -> UndoToken {
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
            sourceURLs: sourceURLs,
            destinationURLs: trashedURLs,
            expiresAt: Date().addingTimeInterval(trashUndoWindow)
        )
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
}
