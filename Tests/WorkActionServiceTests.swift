import AppKit
import PDFKit
import XCTest
@testable import NotchDock

final class WorkActionServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var io: FileIOService!
    private var service: WorkActionService!
    private var officeConverter: MockOfficeConverter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NotchDockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        io = FileIOService(fileManager: .default, outputRoot: tempRoot.appendingPathComponent("Out", isDirectory: true))
        officeConverter = MockOfficeConverter()
        service = WorkActionService(io: io, officeConverter: officeConverter)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        io = nil
        service = nil
        officeConverter = nil
        try super.tearDownWithError()
    }

    func testClassifyImagesPrefersOptimizeImages() throws {
        let image = try makeImage(name: "a.png")
        let plan = service.classify([image])
        XCTAssertEqual(plan.kind, .images)
        XCTAssertEqual(plan.recommendedAction, .optimizeImages)
    }

    func testCompressZipMovesOriginalAndUndoRestores() async throws {
        let source = tempRoot.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: source)

        let result = try await service.execute(.compressZip, inputs: [source])
        XCTAssertEqual(result.action, .compressZip)
        XCTAssertTrue(result.outputs.first?.pathExtension == "zip")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotNil(result.undoToken)

        guard let token = result.undoToken else { return XCTFail("Missing undo token") }
        let undone = await service.undo(token)
        XCTAssertTrue(undone)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testExtractZipCreatesFolder() async throws {
        let source = tempRoot.appendingPathComponent("zip-source.txt")
        try Data("zip".utf8).write(to: source)
        let archive = tempRoot.appendingPathComponent("sample.zip")
        try FileManager.default.zipItem(at: source, to: archive, shouldKeepParent: true)

        let result = try await service.execute(.extractZip, inputs: [archive])
        XCTAssertEqual(result.action, .extractZip)
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputs[0].path))
    }

    func testOptimizePDFKeepsTextReadable() async throws {
        let source = try makeTextPDF(name: "doc.pdf")
        let result = try await service.execute(.optimizePDFKeepText, inputs: [source])
        guard let optimized = result.outputs.first else {
            return XCTFail("Missing optimized output")
        }
        let document = PDFDocument(url: optimized)
        let text = document?.page(at: 0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(text.isEmpty)
    }

    func testClassifyTextDocumentsPrefersTextToPDF() throws {
        let source = tempRoot.appendingPathComponent("note.md")
        try Data("# heading".utf8).write(to: source)
        let plan = service.classify([source])
        XCTAssertEqual(plan.kind, .textDocuments)
        XCTAssertEqual(plan.recommendedAction, .textDocumentToPDF)
    }

    func testClassifyOfficeDocumentsPrefersOfficeToPDF() throws {
        let source = tempRoot.appendingPathComponent("deck.docx")
        try Data("office".utf8).write(to: source)
        let plan = service.classify([source])
        XCTAssertEqual(plan.kind, .officeDocuments)
        XCTAssertEqual(plan.recommendedAction, .officeToPDF)
    }

    func testTextDocumentToPDFCreatesOutput() async throws {
        let source = tempRoot.appendingPathComponent("note.txt")
        try Data("Plain text".utf8).write(to: source)
        let result = try await service.execute(.textDocumentToPDF, inputs: [source])
        XCTAssertEqual(result.outputs.first?.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputs[0].path))
    }

    func testOfficeToPDFUsesConverter() async throws {
        let source = tempRoot.appendingPathComponent("slides.docx")
        try Data("office".utf8).write(to: source)
        let result = try await service.execute(.officeToPDF, inputs: [source])
        XCTAssertEqual(result.outputs.first?.pathExtension, "pdf")
        XCTAssertEqual(officeConverter.convertedInputs, [source])
    }

    func testOfficeToPDFReturnsInstallMessageWhenUnavailable() {
        officeConverter.isAvailableValue = false
        let reason = service.unavailableReason(for: .officeToPDF)
        XCTAssertEqual(reason, "Install LibreOffice to enable Office -> PDF")
    }

    func testImageFormatConversionsCreateFiles() async throws {
        let png = try makeImage(name: "a.png")
        let jpegResult = try await service.execute(.imageToJPEG, inputs: [png])
        XCTAssertEqual(jpegResult.outputs.first?.pathExtension, "jpg")

        let jpeg = jpegResult.outputs[0]
        let pngResult = try await service.execute(.imageToPNG, inputs: [jpeg])
        XCTAssertEqual(pngResult.outputs.first?.pathExtension, "png")
    }

    private func makeImage(name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 180, height: 180))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 180, height: 180)).fill()
        image.unlockFocus()
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else {
            throw WorkActionError.operationFailed("Fixture generation failed")
        }
        try data.write(to: url)
        return url
    }

    private func makeTextPDF(name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw WorkActionError.operationFailed("Cannot create PDF context")
        }
        context.beginPDFPage(nil)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: "Readable PDF text layer").draw(at: CGPoint(x: 40, y: 140), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        try data.write(to: url, options: .atomic)
        return url
    }
}

private final class MockOfficeConverter: OfficeConverting {
    var isAvailableValue = true
    var convertedInputs: [URL] = []

    var isAvailable: Bool { isAvailableValue }
    var unavailableReason: String? {
        isAvailableValue ? nil : "Install LibreOffice to enable Office -> PDF"
    }

    func convertToPDF(inputs: [URL], outputDir: URL, io: FileIOService) throws -> [URL] {
        guard isAvailableValue else {
            throw WorkActionError.operationFailed(unavailableReason ?? "Unavailable")
        }
        convertedInputs = inputs
        return try inputs.map { input in
            let output = io.uniqueFileURL(
                in: outputDir,
                stem: "\(input.deletingPathExtension().lastPathComponent)__officeToPDF__v1",
                ext: "pdf"
            )
            try Data("pdf".utf8).write(to: output)
            return output
        }
    }
}
