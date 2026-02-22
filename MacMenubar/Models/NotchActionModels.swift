import Foundation

enum NotchActionKind: String, Codable, CaseIterable, Identifiable {
    case imageToPDF
    case pdfToImages
    case compressZip
    case extractZip
    case optimizeImages
    case optimizePDFKeepText
    case resizeImages
    case sendToWorkbench
    case moveToTrash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .imageToPDF:
            return "Image -> PDF"
        case .pdfToImages:
            return "PDF -> Images"
        case .compressZip:
            return "Compress (.zip)"
        case .extractZip:
            return "Extract ZIP"
        case .optimizeImages:
            return "Optimize Images"
        case .optimizePDFKeepText:
            return "Optimize PDF (Keep Text)"
        case .resizeImages:
            return "Resize Images"
        case .sendToWorkbench:
            return "Send to Workbench"
        case .moveToTrash:
            return "Move to Trash"
        }
    }

    var symbolName: String {
        switch self {
        case .imageToPDF:
            return "photo.on.rectangle.angled"
        case .pdfToImages:
            return "doc.on.doc"
        case .compressZip:
            return "archivebox"
        case .extractZip:
            return "tray.and.arrow.down"
        case .optimizeImages:
            return "wand.and.stars"
        case .optimizePDFKeepText:
            return "doc.text.magnifyingglass"
        case .resizeImages:
            return "arrow.up.left.and.arrow.down.right"
        case .sendToWorkbench:
            return "shippingbox"
        case .moveToTrash:
            return "trash"
        }
    }
}

enum NotchDropState: Equatable {
    case idle
    case preheat
    case predrag
    case hovering
    case magnetFocus(NotchActionKind)
    case dropCommit(NotchActionKind)
    case processing
    case success
    case failure
}

enum DropContentKind: String, Equatable {
    case images
    case pdfs
    case zipArchives
    case mixed
    case unsupported
}

enum FileOutputPolicy: Equatable {
    case sourceDirectory
}

enum DangerousOperationKind: String, Codable, Equatable {
    case moveToTrash
    case compressAndTrashOriginals
    case replaceWithOptimized
}

struct DroppedFileDescriptor: Identifiable, Equatable {
    let id: String
    let url: URL
    let utType: String
    let fileName: String
    let fileSize: Int64
}

struct UndoReplacement: Equatable {
    let sourceURL: URL
    let generatedURL: URL
}

struct UndoToken: Equatable {
    let operationKind: DangerousOperationKind
    let sourceURLs: [URL]
    let destinationURLs: [URL]
    let replacements: [UndoReplacement]
    let expiresAt: Date
}

struct StorageDelta: Equatable {
    let beforeBytes: Int64
    let afterBytes: Int64

    var reclaimedBytes: Int64 {
        max(0, beforeBytes - afterBytes)
    }

    static let zero = StorageDelta(beforeBytes: 0, afterBytes: 0)
}

struct ActionExecutionResult: Equatable {
    let action: NotchActionKind
    let outputs: [URL]
    let message: String
    let undoToken: UndoToken?
    let spaceDeltaBytes: Int64
    let warnings: [String]
}

struct DropClassification: Equatable {
    let kind: DropContentKind
    let descriptors: [DroppedFileDescriptor]
    let recommendedAction: NotchActionKind?
    let secondaryActions: [NotchActionKind]
}

protocol FileActionExecuting: AnyObject {
    func classify(urls: [URL]) -> DropClassification
    func availableActions(for kind: DropContentKind) -> [NotchActionKind]
    func execute(action: NotchActionKind, inputs: [DroppedFileDescriptor], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult
    func undo(token: UndoToken) -> Bool
    func workbenchFolderURL() -> URL
}

protocol WorkbenchStoring: AnyObject {
    func store(urls: [URL]) throws -> [URL]
    func list() -> [URL]
    func clear() throws
    var folderURL: URL { get }
}

enum FileActionError: Error, LocalizedError {
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
