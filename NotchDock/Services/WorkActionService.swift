import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

enum WorkActionError: Error, LocalizedError {
    case unsupportedInput
    case failedToReadImage(URL)
    case failedToReadPDF(URL)
    case failedToReadText(URL)
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
        case .failedToReadText(let url):
            "Cannot read text document: \(url.lastPathComponent)"
        case .failedToWriteOutput(let url):
            "Cannot write output: \(url.lastPathComponent)"
        case .operationFailed(let message):
            message
        }
    }
}

/// @unchecked Sendable type-erasing box for OfficeConverting.
/// Safe: all production conformers (LibreOfficeConverter) are final classes whose only
/// stored property is an immutable `let fileManager: FileManager` (documented thread-safe).
/// Avoids adding `Sendable` to the public protocol, which would cascade to test mocks.
private struct AnyOfficeConverter: @unchecked Sendable {
    private let base: any OfficeConverting
    var unavailableReason: String? { base.unavailableReason }
    func convertToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        try base.convertToPDF(inputs: inputs, outputDir: outputDir, io: io)
    }
    init(_ base: any OfficeConverting) { self.base = base }
}

final class WorkActionService: WorkActionExecuting {
    private let io: FileIOService
    private let undoWindow: TimeInterval
    private let officeConverter: AnyOfficeConverter

    init(
        io: FileIOService = FileIOService(),
        undoWindow: TimeInterval = 8,
        officeConverter: OfficeConverting = LibreOfficeConverter()
    ) {
        self.io = io
        self.undoWindow = undoWindow
        self.officeConverter = AnyOfficeConverter(officeConverter)
    }

    func classify(_ inputs: [URL]) -> DropPlan {
        guard !inputs.isEmpty else {
            return DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
        }

        let imageOnly = inputs.allSatisfy(Self.isImageFile(_:))
        let pdfOnly = inputs.allSatisfy(Self.isPDFFile(_:))
        let textOnly = inputs.allSatisfy(Self.isTextDocument(_:))
        let officeOnly = inputs.allSatisfy(Self.isOfficeDocument(_:))
        let zipOnly = inputs.allSatisfy(Self.isZipFile(_:))

        if imageOnly {
            return DropPlan(
                kind: .images,
                recommendedAction: .optimizeImages,
                secondaryActions: [.resizeImages, .imageToPDF, .imageToJPEG, .imageToPNG, .imageToHEIC, .imageToWebP, .compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if pdfOnly {
            return DropPlan(
                kind: .pdfs,
                recommendedAction: .optimizePDFKeepText,
                secondaryActions: [.pdfToImages, .compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if textOnly {
            return DropPlan(
                kind: .textDocuments,
                recommendedAction: .textDocumentToPDF,
                secondaryActions: [.compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if officeOnly {
            return DropPlan(
                kind: .officeDocuments,
                recommendedAction: .officeToPDF,
                secondaryActions: [.compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        if zipOnly {
            return DropPlan(
                kind: .zipArchives,
                recommendedAction: .extractZip,
                secondaryActions: [.compressZip, .sendToWorkbench, .moveToTrash]
            )
        }
        return DropPlan(
            kind: .mixed,
            recommendedAction: .compressZip,
            secondaryActions: [.sendToWorkbench, .moveToTrash]
        )
    }

    func unavailableReason(for action: WorkActionKind) -> String? {
        switch action {
        case .officeToPDF:
            return officeConverter.unavailableReason
        case .imageToHEIC:
            return Self.supportsDestination(type: .heic) ? nil : "HEIC export is unavailable on this Mac"
        case .imageToWebP:
            return Self.supportsDestination(type: .webP) ? nil : "WebP export is unavailable on this Mac"
        default:
            return nil
        }
    }

    func execute(_ action: WorkActionKind, inputs: [URL]) async throws -> DropExecutionResult {
        try await Task.detached(priority: .userInitiated) { [io, undoWindow, officeConverter] in
            guard !inputs.isEmpty else { throw WorkActionError.unsupportedInput }
            let outputDir = try io.datedOutputFolder()

            switch action {
            case .imageToPDF:
                let output = try Self.imageToPDF(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(action: action, outputs: [output], reclaimedBytes: 0, undoToken: nil, message: "Created \(output.lastPathComponent)", warnings: [])

            case .pdfToImages:
                let outputs = try Self.pdfToImages(inputs: inputs, outputDir: outputDir, io: io, format: .png)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Exported \(outputs.count) image file(s)", warnings: [])

            case .officeToPDF:
                let outputs = try officeConverter.convertToPDF(inputs: inputs.filter(Self.isOfficeDocument(_:)), outputDir: outputDir, io: io)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) Office file(s) to PDF", warnings: [])

            case .textDocumentToPDF:
                let outputs = try Self.convertTextDocumentsToPDF(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) text file(s) to PDF", warnings: [])

            case .imageToJPEG:
                let outputs = try Self.convertImageFormat(inputs: inputs, outputDir: outputDir, io: io, format: .jpeg)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) image(s) to JPEG", warnings: [])

            case .imageToPNG:
                let outputs = try Self.convertImageFormat(inputs: inputs, outputDir: outputDir, io: io, format: .png)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) image(s) to PNG", warnings: [])

            case .imageToHEIC:
                let outputs = try Self.convertImageFormat(inputs: inputs, outputDir: outputDir, io: io, format: .heic)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) image(s) to HEIC", warnings: [])

            case .imageToWebP:
                let outputs = try Self.convertImageFormat(inputs: inputs, outputDir: outputDir, io: io, format: .webP)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Converted \(outputs.count) image(s) to WebP", warnings: [])

            case .compressZip:
                let beforeBytes = io.totalFileSize(urls: inputs)
                let archive = try Self.compressZip(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, beforeBytes - io.fileSize(at: archive))
                let undo = try io.moveToTrash(inputs, generatedOutputs: [archive], undoWindow: undoWindow)
                return DropExecutionResult(action: action, outputs: [archive], reclaimedBytes: reclaimed, undoToken: undo, message: "ZIP complete · reclaimed \(Self.byteString(reclaimed))", warnings: [])

            case .extractZip:
                let outputs = try Self.extractZip(inputs: inputs, outputDir: outputDir, io: io)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Extracted \(outputs.count) archive(s)", warnings: [])

            case .optimizeImages:
                let outputs = try Self.optimizeImages(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: reclaimed, undoToken: undo, message: "Optimized \(outputs.count) image(s) · reclaimed \(Self.byteString(reclaimed))", warnings: [])

            case .optimizePDFKeepText:
                let outputs = try Self.optimizePDF(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: reclaimed, undoToken: undo, message: "Optimized \(outputs.count) PDF(s) · reclaimed \(Self.byteString(reclaimed))", warnings: [])

            case .resizeImages:
                let outputs = try Self.resizeImages(inputs: inputs, outputDir: outputDir, io: io)
                let reclaimed = max(0, io.totalFileSize(urls: inputs) - io.totalFileSize(urls: outputs))
                let undo = try io.moveToTrash(inputs, generatedOutputs: outputs, undoWindow: undoWindow)
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: reclaimed, undoToken: undo, message: "Resized \(outputs.count) image(s) · reclaimed \(Self.byteString(reclaimed))", warnings: [])

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
                return DropExecutionResult(action: action, outputs: outputs, reclaimedBytes: 0, undoToken: nil, message: "Collected \(outputs.count) file(s) in Workbench", warnings: [])

            case .moveToTrash:
                let undo = try io.moveToTrash(inputs, generatedOutputs: [], undoWindow: undoWindow)
                return DropExecutionResult(action: action, outputs: undo.trashedURLs, reclaimedBytes: io.totalFileSize(urls: inputs), undoToken: undo, message: "Moved \(inputs.count) file(s) to Trash", warnings: [])
            }
        }.value
    }

    func undo(_ token: UndoToken) async -> Bool {
        await Task.detached(priority: .userInitiated) { [io] in
            io.undo(token)
        }.value
    }

    private static func imageToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> URL {
        let images = inputs.filter(isImageFile(_:))
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

    private static func pdfToImages(inputs: [URL], outputDir: URL, io: FileIOService, format: ImageFormat) throws -> [URL] {
        let pdfs = inputs.filter(isPDFFile(_:))
        guard !pdfs.isEmpty else { throw WorkActionError.unsupportedInput }

        var outputs: [URL] = []
        for input in pdfs {
            guard let doc = PDFDocument(url: input) else { throw WorkActionError.failedToReadPDF(input) }
            for pageIndex in 0..<doc.pageCount {
                guard let page = doc.page(at: pageIndex) else { continue }
                let output = io.uniqueFileURL(
                    in: outputDir,
                    stem: "\(input.deletingPathExtension().lastPathComponent)__\(WorkActionKind.pdfToImages.rawValue)__v1-p\(pageIndex + 1)",
                    ext: format.fileExtension
                )
                let data = try renderPDFPage(page, format: format)
                try data.write(to: output, options: .atomic)
                outputs.append(output)
            }
        }
        return outputs
    }

    private static func convertTextDocumentsToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let documents = inputs.filter(isTextDocument(_:))
        guard !documents.isEmpty else { throw WorkActionError.unsupportedInput }

        var outputs: [URL] = []
        for input in documents {
            let attributed = try attributedText(for: input)
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(input.deletingPathExtension().lastPathComponent)__\(WorkActionKind.textDocumentToPDF.rawValue)__v1",
                ext: "pdf"
            )
            let data = try pdfData(for: attributed)
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    private static func convertImageFormat(inputs: [URL], outputDir: URL, io: FileIOService, format: ImageFormat) throws -> [URL] {
        let images = inputs.filter(isImageFile(_:))
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }
        guard supportsDestination(type: format.utType) else {
            throw WorkActionError.operationFailed("\(format.displayName) export is unavailable on this Mac")
        }

        var outputs: [URL] = []
        for imageURL in images {
            guard let image = NSImage(contentsOf: imageURL),
                  let cgImage = cgImage(from: image) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(imageURL.deletingPathExtension().lastPathComponent)__\(format.actionSuffix)__v1",
                ext: format.fileExtension
            )
            try writeCGImage(cgImage, to: output, format: format)
            outputs.append(output)
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
        let images = inputs.filter(isImageFile(_:))
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }

        var outputs: [URL] = []
        for imageURL in images {
            guard let image = NSImage(contentsOf: imageURL),
                  let bitmap = bitmapRep(from: image) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }

            let hasAlpha = bitmap.hasAlpha
            let format: ImageFormat = hasAlpha ? .png : .jpeg
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(imageURL.deletingPathExtension().lastPathComponent)__\(WorkActionKind.optimizeImages.rawValue)__v1",
                ext: format.fileExtension
            )
            try writeBitmap(bitmap, to: output, format: format, qualityOverride: format.defaultCompression)
            outputs.append(output)
        }
        return outputs
    }

    private static func optimizePDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        let pdfs = inputs.filter(isPDFFile(_:))
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
        let images = inputs.filter(isImageFile(_:))
        guard !images.isEmpty else { throw WorkActionError.unsupportedInput }

        var outputs: [URL] = []
        for imageURL in images {
            guard let source = NSImage(contentsOf: imageURL),
                  let resized = resizedImage(source, maxLongEdge: 2048),
                  let bitmap = bitmapRep(from: resized) else {
                throw WorkActionError.failedToReadImage(imageURL)
            }

            let format: ImageFormat = bitmap.hasAlpha ? .png : .jpeg
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(imageURL.deletingPathExtension().lastPathComponent)__\(WorkActionKind.resizeImages.rawValue)__v1",
                ext: format.fileExtension
            )
            try writeBitmap(bitmap, to: output, format: format, qualityOverride: format == .png ? nil : 0.78)
            outputs.append(output)
        }
        return outputs
    }

    private static func attributedText(for url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            let string = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: string, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ])
        }
        if ext == "rtf" {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
        guard let string = try? String(contentsOf: url, encoding: .utf8) else {
            throw WorkActionError.failedToReadText(url)
        }
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private static func pdfData(for attributedString: NSAttributedString) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 44
        let frameRect = pageRect.insetBy(dx: margin, dy: margin)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let data = NSMutableData()
        var mediaBox = pageRect

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw WorkActionError.operationFailed("Unable to render PDF output.")
        }

        var range = CFRange(location: 0, length: 0)
        repeat {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1, y: -1)
            let path = CGMutablePath()
            path.addRect(frameRect)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            range.location += visible.length
            context.endPDFPage()
        } while range.location < attributedString.length

        context.closePDF()
        return data as Data
    }

    private static func renderPDFPage(_ page: PDFPage, format: ImageFormat) throws -> Data {
        let bounds = page.bounds(for: .mediaBox)
        let scaledSize = CGSize(width: max(1, bounds.width * 2), height: max(1, bounds.height * 2))
        let image = NSImage(size: scaledSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: scaledSize)).fill()
        guard let cgContext = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            throw WorkActionError.operationFailed("Unable to render PDF page.")
        }
        cgContext.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: cgContext)
        image.unlockFocus()

        guard let cgImage = cgImage(from: image) else {
            throw WorkActionError.operationFailed("Unable to render PDF page.")
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try writeCGImage(cgImage, to: tempURL, format: format)
        return try Data(contentsOf: tempURL)
    }

    private static func writeBitmap(_ bitmap: NSBitmapImageRep, to url: URL, format: ImageFormat, qualityOverride: CGFloat?) throws {
        switch format {
        case .jpeg, .png:
            let fileType: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
            var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
            if let quality = qualityOverride, format == .jpeg {
                properties[.compressionFactor] = quality
            }
            guard let data = bitmap.representation(using: fileType, properties: properties) else {
                throw WorkActionError.failedToWriteOutput(url)
            }
            try data.write(to: url, options: .atomic)
        case .heic, .webP:
            guard let cgImage = bitmap.cgImage else {
                throw WorkActionError.failedToWriteOutput(url)
            }
            try writeCGImage(cgImage, to: url, format: format, qualityOverride: qualityOverride)
        }
    }

    private static func writeCGImage(_ cgImage: CGImage, to url: URL, format: ImageFormat, qualityOverride: CGFloat? = nil) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw WorkActionError.failedToWriteOutput(url)
        }
        let quality = qualityOverride ?? format.defaultCompression
        let options: CFDictionary = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            throw WorkActionError.failedToWriteOutput(url)
        }
    }

    private static func bitmapRep(from image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return bitmap
        }
        guard let data = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        if let bitmap = bitmapRep(from: image), let cgImage = bitmap.cgImage {
            return cgImage
        }
        return nil
    }

    private static func resizedImage(_ image: NSImage, maxLongEdge: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }

    private static func supportsDestination(type: UTType) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(type.identifier)
    }

    private static func contentType(for url: URL) -> UTType {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
    }

    private static func isImageFile(_ url: URL) -> Bool {
        contentType(for: url).conforms(to: .image)
    }

    private static func isPDFFile(_ url: URL) -> Bool {
        contentType(for: url).conforms(to: .pdf)
    }

    private static func isZipFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    private static func isTextDocument(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["txt", "rtf", "md", "markdown"].contains(ext)
    }

    private static func isOfficeDocument(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["doc", "docx", "ppt", "pptx", "xls", "xlsx"].contains(ext)
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum ImageFormat {
    case jpeg
    case png
    case heic
    case webP

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .webP: "webp"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .webP: .webP
        }
    }

    var defaultCompression: CGFloat {
        switch self {
        case .jpeg: 0.72
        case .png: 1
        case .heic: 0.65
        case .webP: 0.70
        }
    }

    var actionSuffix: String {
        switch self {
        case .jpeg: WorkActionKind.imageToJPEG.rawValue
        case .png: WorkActionKind.imageToPNG.rawValue
        case .heic: WorkActionKind.imageToHEIC.rawValue
        case .webP: WorkActionKind.imageToWebP.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .webP: "WebP"
        }
    }
}
