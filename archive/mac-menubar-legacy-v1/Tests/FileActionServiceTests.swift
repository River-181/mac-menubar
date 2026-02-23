import AppKit
import PDFKit
import XCTest
@testable import MacMenubar

final class FileActionServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var workbenchDirectory: URL!
    private var service: FileActionService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MacMenubarTests-\(UUID().uuidString)", isDirectory: true)
        workbenchDirectory = temporaryDirectory.appendingPathComponent("Workbench", isDirectory: true)

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let workbench = WorkbenchStore(folderURL: workbenchDirectory)
        service = FileActionService(workbenchStore: workbench)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        service = nil
        workbenchDirectory = nil
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testClassifyImagesRecommendsOptimizeImages() throws {
        let imageA = try makeImage(named: "a.png")
        let imageB = try makeImage(named: "b.png")

        let classification = service.classify(urls: [imageA, imageB])

        XCTAssertEqual(classification.kind, .images)
        XCTAssertEqual(classification.recommendedAction, .optimizeImages)
        XCTAssertTrue(classification.secondaryActions.contains(.imageToPDF))
        XCTAssertEqual(service.availableActions(for: classification.kind), [.optimizeImages, .resizeImages, .imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash])
    }

    func testCompressZipMovesOriginalToTrashAndUndoRestores() throws {
        let source = temporaryDirectory.appendingPathComponent("note.txt")
        try Data("hello storage".utf8).write(to: source)

        let descriptor = DroppedFileDescriptor(
            id: source.path,
            url: source,
            utType: "public.plain-text",
            fileName: source.lastPathComponent,
            fileSize: 0
        )

        let result = try service.execute(action: .compressZip, inputs: [descriptor], outputPolicy: .sourceDirectory)

        guard let archive = result.outputs.first else {
            XCTFail("Missing archive output")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotNil(result.undoToken)

        guard let token = result.undoToken else {
            XCTFail("Expected undo token")
            return
        }

        XCTAssertTrue(service.undo(token: token))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testExtractZipProducesDirectory() throws {
        let source = temporaryDirectory.appendingPathComponent("sample.txt")
        try Data("zip me".utf8).write(to: source)

        let zipURL = temporaryDirectory.appendingPathComponent("sample.zip")
        try runDittoCompression(source: source, destination: zipURL)

        let descriptor = DroppedFileDescriptor(
            id: zipURL.path,
            url: zipURL,
            utType: "public.zip-archive",
            fileName: zipURL.lastPathComponent,
            fileSize: 0
        )

        let result = try service.execute(action: .extractZip, inputs: [descriptor], outputPolicy: .sourceDirectory)

        XCTAssertEqual(result.action, .extractZip)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputs[0].path))
    }

    func testOptimizePDFKeepTextProducesReadableTextAndSupportsUndo() throws {
        let sourcePDF = try makeTextPDF(named: "doc.pdf")
        let descriptor = DroppedFileDescriptor(
            id: sourcePDF.path,
            url: sourcePDF,
            utType: "com.adobe.pdf",
            fileName: sourcePDF.lastPathComponent,
            fileSize: 0
        )

        let result = try service.execute(action: .optimizePDFKeepText, inputs: [descriptor], outputPolicy: .sourceDirectory)

        guard let optimized = result.outputs.first else {
            XCTFail("Expected optimized PDF")
            return
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: optimized.path))

        let optimizedDoc = PDFDocument(url: optimized)
        let text = optimizedDoc?.page(at: 0)?.string ?? ""
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        guard let token = result.undoToken else {
            XCTFail("Expected undo token for optimize PDF")
            return
        }

        XCTAssertTrue(service.undo(token: token))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePDF.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: optimized.path))
    }

    private func makeImage(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 240, height: 240))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 240, height: 240)).fill()
        image.unlockFocus()

        guard
            let tiffData = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiffData),
            let pngData = rep.representation(using: .png, properties: [:])
        else {
            throw FileActionError.commandFailed("Unable to produce PNG fixture")
        }

        try pngData.write(to: url)
        return url
    }

    private func makeTextPDF(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let data = NSMutableData()

        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw FileActionError.commandFailed("Failed to create PDF context")
        }

        context.beginPDFPage(nil)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: "Storage optimization keeps this text.").draw(at: CGPoint(x: 40, y: 140), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        try data.write(to: url, options: .atomic)
        return url
    }

    private func runDittoCompression(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
