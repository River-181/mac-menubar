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

    func testClassifyImagesReturnsImageToPDFDefault() throws {
        let imageA = try makeImage(named: "a.png")
        let imageB = try makeImage(named: "b.png")

        let classification = service.classify(urls: [imageA, imageB])

        XCTAssertEqual(classification.kind, .images)
        XCTAssertEqual(classification.defaultAction, .imageToPDF)
        XCTAssertEqual(service.availableActions(for: classification.kind), [.imageToPDF, .compressZip, .sendToWorkbench, .moveToTrash])
    }

    func testImageToPDFResolvesFileNameCollisionWithSuffix() throws {
        let image = try makeImage(named: "sample.png")
        let preExisting = temporaryDirectory.appendingPathComponent("sample.pdf")
        try Data("existing".utf8).write(to: preExisting)

        let descriptor = DroppedFileDescriptor(
            id: image.path,
            url: image,
            utType: "public.png",
            fileName: image.lastPathComponent,
            fileSize: 0
        )

        let result = try service.execute(action: .imageToPDF, inputs: [descriptor], outputPolicy: .sourceDirectory)

        XCTAssertEqual(result.action, .imageToPDF)
        XCTAssertTrue(result.outputs.first?.lastPathComponent.hasPrefix("sample_1") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputs[0].path))
    }

    func testMoveToTrashThenUndoRestoresFile() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: fileURL)

        let descriptor = DroppedFileDescriptor(
            id: fileURL.path,
            url: fileURL,
            utType: "public.plain-text",
            fileName: fileURL.lastPathComponent,
            fileSize: 5
        )

        let result = try service.execute(action: .moveToTrash, inputs: [descriptor], outputPolicy: .sourceDirectory)
        XCTAssertNotNil(result.undoToken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        guard let token = result.undoToken else {
            XCTFail("Expected undo token")
            return
        }

        XCTAssertTrue(service.undo(token: token))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private func makeImage(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
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
}
