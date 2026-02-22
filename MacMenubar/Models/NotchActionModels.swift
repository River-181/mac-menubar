import Foundation

enum NotchActionKind: String, Codable, CaseIterable, Identifiable {
    case imageToPDF
    case pdfToImages
    case compressZip
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
        case .sendToWorkbench:
            return "shippingbox"
        case .moveToTrash:
            return "trash"
        }
    }
}

enum NotchDropState: Equatable {
    case idle
    case hovering
    case processing
    case success
    case failure
}

enum DropContentKind: String, Equatable {
    case images
    case pdfs
    case mixed
    case unsupported
}

enum FileOutputPolicy: Equatable {
    case sourceDirectory
}

struct DroppedFileDescriptor: Identifiable, Equatable {
    let id: String
    let url: URL
    let utType: String
    let fileName: String
    let fileSize: Int64
}

struct UndoToken: Equatable {
    let sourceURLs: [URL]
    let destinationURLs: [URL]
    let expiresAt: Date
}

struct ActionExecutionResult: Equatable {
    let action: NotchActionKind
    let outputs: [URL]
    let message: String
    let undoToken: UndoToken?
}

struct DropClassification: Equatable {
    let kind: DropContentKind
    let descriptors: [DroppedFileDescriptor]
    let defaultAction: NotchActionKind?
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
