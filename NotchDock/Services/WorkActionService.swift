import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

enum WorkActionError: Error, LocalizedError {
    case unsupportedInput
    case failedToReadImage(URL)
    case failedToReadPDF(URL)
    case failedToWriteOutput(URL)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            "Unsupported input."
        case .failedToReadImage(let url):
            "Cannot read image: \(url.lastPathComponent)"
        case .failedToReadPDF(let url):
            "Cannot read PDF: \(url.lastPathComponent)"
        case .failedToWriteOutput(let url):
            "Cannot write output: \(url.lastPathComponent)"
        case .operationFailed(let message):
            message
        }
    }
}

final class WorkActionService: WorkActionExecuting {
    private let io: FileIOService
    private let undoWindow: TimeInterval

    init(io: FileIOService = FileIOService(), undoWindow: TimeInterval = 8) {
        self.io = io
        self.undoWindow = undoWindow
    }

    func classify(_ inputs: [URL]) -> DropPlan {
        guard !inputs.isEmpty else {
            return DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
        }
        let types = inputs.map { Self.contentType(for: $0) }
        let imageOnly = types.allSatisfy { $0.conforms(to: UTType.image) }
        let pdfOnly = types.allSatisfy { $0.conforms(to: UTType.pdf) }
        let zipOnly = inputs.allSatisfy(Self.isZipFile(_:))
        let mixed = !imageOnly && !pdfOnly && !zipOnly

        if imageOnly {
            return DropPlan(
                kind: .images,
                recommendedAction: .optimizeImages,
                secondaryActions: [.resizeImages, .imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if pdfOnly {
            return DropPlan(
                kind: .pdfs,
                recommendedAction: .optimizePDFKeepText,
                secondaryActions: [.pdfToImages, .compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if zipOnly {
            return DropPlan(
                kind: .zipArchives,
                recommendedAction: .extractZip,
                secondaryActions: [.compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if mixed {
            return DropPlan(
                kind: .mixed,
                recommendedAction: .compressZip,
                secondaryActions: [.sendToWorkbench, .moveToTrash]
            )
        }
        return DropPlan(
            kind: .unsupported,
            recommendedAction: .sendToWorkbench,
            secondaryActions: [.compressZip, .moveToTrash]
        )
    }

    func execute(_ action: WorkActionKind, inputs: [URL]) async throws -> DropExecutionResult {
        try await Task.detached(priority: .userInitiated) { [io, undoWindow] in
            guard !inputs.isEmpty else { throw WorkActionError.unsupportedInput }
            let outputDir = try io.datedOutputFolder()

            switch action {
            case .imageToPDF:
                let output = try Self.imageToPDF(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(
                    action: action,
                    outputs: [output],
                    reclaimedBytes: 0,
                    undoToken: nil,
                    message: "Created \(output.lastPathComponent)",
                    warnings: []
                )

            case .pdfToImages:
                let outputs = try Self.pdfToImages(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: 0,
                    undoToken: nil,
                    message: "Exported \(outputs.count) image file(s)",
                    warnings: []
                )

            case .compressZip:
                let beforeBytes = io.totalFileSize(urls: inputs)
                let archive = try Self.compressZip(inputs: inputs, outputDir: outputDir, io: io)
                let afterBytes = io.fileSize(at: archive)
                let reclaimed = max(0, beforeBytes - afterBytes)
                let undo = try io.moveToTrash(inputs, generatedOutputs: [archive], undoWindow: undoWindow)
                return DropExecutionResult(
                    action: action,
                    outputs: [archive],
                    reclaimedBytes: reclaimed,
                    undoToken: undo,
                    message: "ZIP complete · reclaimed \(Self.byteString(reclaimed))",
                    warnings: []
                )

            case .extractZip:
                let outputs = try Self.extractZip(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: 0,
                    undoToken: nil,
                    message: "Extracted \(outputs.count) archive(s)",
                    warnings: []
                )

            case .optimizeImages:
                let outputs = try Self.optimizeImages(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: reclaimed,
                    undoToken: undo,
                    message: "Optimized \(outputs.count) image(s) · reclaimed \(Self.byteString(reclaimed))",
                    warnings: []
                )

            case .optimizePDFKeepText:
                let outputs = try Self.optimizePDF(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: reclaimed,
                    undoToken: undo,
                    message: "Optimized \(outputs.count) PDF(s) · reclaimed \(Self.byteString(reclaimed))",
                    warnings: []
                )

            case .resizeImages:
                let outputs = try Self.resizeImages(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: reclaimed,
                    undoToken: undo,
                    message: "Resized \(outputs.count) image(s) · reclaimed \(Self.byteString(reclaimed))",
                    warnings: []
                )

            case .sendToWorkbench:
                let folder = try io.ensureWorkbenchFolder()
                var outputs: [URL] = []
                for input in inputs {
                    let ext = input.pathExtension
                    let stem = "\(input.deletingPathExtension().lastPathComponent)__workbench__v1"
                    let target = io.uniqueFileURL(in: folder, stem: stem, ext: ext)
                    try io.fileManager.copyItem(at: input, to: target)
                    outputs.append(target)
                }
                return DropExecutionResult(
                    action: action,
                    outputs: outputs,
                    reclaimedBytes: 0,
                    undoToken: nil,
                    message: "Collected \(outputs.count) file(s) in Workbench",
                    warnings: []
                )

            case .moveToTrash:
                let undo = try io.moveToTrash(inputs, generatedOutputs: [], undoWindow: undoWindow)
                return DropExecutionResult(
                    action: action,
                    outputs: undo.trashedURLs,
                    reclaimedBytes: io.totalFileSize(urls: inputs),
                    undoToken: undo,
                    message: "Moved \(inputs.count) file(s) to Trash",
                    warnings: []
                )
            }
        }.value
    }

    func undo(_ token: UndoToken) async -> Bool {
        await Task.detached(priority: .userInitiated) { [io] in
            io.undo(token)
        }.value
    }

    private static func imageToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> URL {
        let images = inputs.filter { contentType(for: $0).conforms(to: .image) }
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }
        let pdf = PDFDocument()
        for (index, imageURL) in images.enumerated() {
            guard let image = NSImage(contentsOf: imageURL), let page = PDFPage(image: image) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }
            pdf.insert(page, at: index)
        }
        let output = io.uniqueFileURL(
            in: outputDir,
            stem: "\(images[0].deletingPathExtension().lastPathComponent)__\(WorkActionKind.imageToPDF.rawValue)__v1",
            ext: "pdf"
        )
        guard pdf.write(to: output) else { throw WorkActionError.failedToWriteOutput(output) }
        return output
    }

    private static func pdfToImages(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let pdfs = inputs.filter { contentType(for: $0).conforms(to: .pdf) }
        guard !pdfs.isEmpty else { throw WorkActionError.unsupportedInput }
        var outputs: [URL] = []
        for input in pdfs {
            guard let doc = PDFDocument(url: input) else { throw WorkActionError.failedToReadPDF(input) }
            for pageIndex in 0..<doc.pageCount {
                guard let page = doc.page(at: pageIndex) else { continue }
                let output = io.uniqueFileURL(
                    in: outputDir,
                    stem: "\(input.deletingPathExtension().lastPathComponent)__\(WorkActionKind.pdfToImages.rawValue)__v1-p\(pageIndex + 1)",
                    ext: "png"
                )
                let data = try renderPDFPageToPNG(page: page)
                try data.write(to: output, options: .atomic)
                outputs.append(output)
            }
        }
        return outputs
    }

    private static func compressZip(inputs: [URL], outputDir: URL, io: FileIOService) throws -> URL {
        let stem = inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent : "batch"
        let output = io.uniqueFileURL(
            in: outputDir,
            stem: "\(stem)__\(WorkActionKind.compressZip.rawValue)__v1",
            ext: "zip"
        )
        if inputs.count == 1 {
            try io.fileManager.zipItem(at: inputs[0], to: output, shouldKeepParent: true, compressionMethod: .deflate)
            return output
        }
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NotchDockZip-\(UUID().uuidString)", isDirectory: true)
        try io.fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? io.fileManager.removeItem(at: tempRoot) }
        for input in inputs {
            try io.fileManager.copyItem(at: input, to: tempRoot.appendingPathComponent(input.lastPathComponent))
        }
        try io.fileManager.zipItem(at: tempRoot, to: output, shouldKeepParent: true, compressionMethod: .deflate)
        return output
    }

    private static func extractZip(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let archives = inputs.filter(isZipFile(_:))
        guard !archives.isEmpty else { throw WorkActionError.unsupportedInput }
        var outputs: [URL] = []
        for archive in archives {
            let dest = io.uniqueDirectoryURL(
                in: outputDir,
                stem: "\(archive.deletingPathExtension().lastPathComponent)__\(WorkActionKind.extractZip.rawValue)__v1"
            )
            try io.fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            try io.fileManager.unzipItem(at: archive, to: dest)
            outputs.append(dest)
        }
        return outputs
    }

    private static func optimizeImages(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let images = inputs.filter { contentType(for: $0).conforms(to: .image) }
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }
        var outputs: [URL] = []
        for imageURL in images {
            guard let image = NSImage(contentsOf: imageURL),
                  let bitmap = bitmapRep(from: image) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }
            let hasAlpha = bitmap.hasAlpha
            let ext = hasAlpha ? "png" : "jpg"
            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
            let quality: CGFloat = hasAlpha ? 0.82 : 0.72
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(imageURL.deletingPathExtension().lastPathComponent)__\(WorkActionKind.optimizeImages.rawValue)__v1",
                ext: ext
            )
            guard let data = bitmap.representation(using: type, properties: [.compressionFactor: quality]) else {
                throw WorkActionError.failedToWriteOutput(output)
            }
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    private static func optimizePDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let pdfs = inputs.filter { contentType(for: $0).conforms(to: .pdf) }
        guard !pdfs.isEmpty else { throw WorkActionError.unsupportedInput }
        var outputs: [URL] = []
        for pdfURL in pdfs {
            guard let doc = PDFDocument(url: pdfURL) else { throw WorkActionError.failedToReadPDF(pdfURL) }
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(pdfURL.deletingPathExtension().lastPathComponent)__\(WorkActionKind.optimizePDFKeepText.rawValue)__v1",
                ext: "pdf"
            )
            guard doc.write(to: output) else { throw WorkActionError.failedToWriteOutput(output) }
            outputs.append(output)
        }
        return outputs
    }

    private static func resizeImages(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let images = inputs.filter { contentType(for: $0).conforms(to: .image) }
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }
        var outputs: [URL] = []
        for imageURL in images {
            guard let source = NSImage(contentsOf: imageURL),
                  let resized = resizedImage(source, maxLongEdge: 2048),
                  let bitmap = bitmapRep(from: resized) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }
            let hasAlpha = bitmap.hasAlpha
            let ext = hasAlpha ? "png" : "jpg"
            let type: NSBitmapImageRep.FileType = hasAlpha ? .png : .jpeg
            let quality: CGFloat = hasAlpha ? 0.85 : 0.78
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(imageURL.deletingPathExtension().lastPathComponent)__\(WorkActionKind.resizeImages.rawValue)__v1",
                ext: ext
            )
            guard let data = bitmap.representation(using: type, properties: [.compressionFactor: quality]) else {
                throw WorkActionError.failedToWriteOutput(output)
            }
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    private static func contentType(for url: URL) -> UTType {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
    }

    private static func isZipFile(_ url: URL) -> Bool {
        let type = contentType(for: url)
        return type.conforms(to: .zip) || url.pathExtension.lowercased() == "zip"
    }

    private static func bitmapRep(from image: NSImage) -> NSBitmapImageRep? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return NSBitmapImageRep(cgImage: cg)
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private static func resizedImage(_ image: NSImage, maxLongEdge: CGFloat) -> NSImage? {
        let sourceSize = image.size
        let longEdge = max(sourceSize.width, sourceSize.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1.0, maxLongEdge / longEdge)
        let newSize = NSSize(width: floor(sourceSize.width * scale), height: floor(sourceSize.height * scale))
        guard newSize.width > 0, newSize.height > 0 else { return nil }
        let rendered = NSImage(size: newSize)
        rendered.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        rendered.unlockFocus()
        return rendered
    }

    private static func renderPDFPageToPNG(page: PDFPage) throws -> Data {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw WorkActionError.operationFailed("Cannot create bitmap")
        }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw WorkActionError.operationFailed("Cannot create graphics context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(NSColor.white.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw WorkActionError.operationFailed("Cannot encode PNG")
        }
        return data
    }

    private static func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
