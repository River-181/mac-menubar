import AppKit
import Foundation
import UniformTypeIdentifiers

enum OverlayState: String, Codable, CaseIterable {
    case hidden
    case armed
    case peek
    case expand
    case processing
}

extension OverlayState {
    var capsuleSize: CGSize {
        switch self {
        case .hidden:
            .zero
        case .armed:
            CGSize(width: 214, height: 40)
        case .peek:
            CGSize(width: 404, height: 92)
        case .expand, .processing:
            CGSize(width: 900, height: 224)
        }
    }

    var panelSize: CGSize {
        let size = capsuleSize
        return CGSize(width: max(30, size.width + 16), height: max(30, size.height + 16))
    }
}

enum OverlayInteractionMode: String, Codable, Equatable {
    case click
    case drag
}

enum OverlayEvent: Equatable {
    case pointerEnterTrigger
    case pointerExitTrigger
    case dragBegan
    case dragMoved
    case dragEnded
    case clickCapsule
    case esc
    case dropCommitted
}

enum TriggerState: String, Codable, Equatable {
    case outside
    case entering
    case inside
    case exiting
}

enum DropHubState: Equatable {
    case idle
    case preview
    case focused(WorkActionKind)
    case processing
    case success
    case failure
}

struct DropTelemetry: Equatable {
    let point: CGPoint
    let velocity: CGVector
    let timestamp: TimeInterval
}

enum WorkActionKind: String, Codable, CaseIterable, Identifiable {
    case imageToPDF
    case pdfToImages
    case officeToPDF
    case textDocumentToPDF
    case imageToJPEG
    case imageToPNG
    case imageToHEIC
    case imageToWebP
    case compressZip
    case extractZip
    case optimizeImages
    case optimizePDFKeepText
    case resizeImages
    case sendToWorkbench
    case moveToTrash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imageToPDF: "Image -> PDF"
        case .pdfToImages: "PDF -> Images"
        case .officeToPDF: "Office -> PDF"
        case .textDocumentToPDF: "Text -> PDF"
        case .imageToJPEG: "Image -> JPEG"
        case .imageToPNG: "Image -> PNG"
        case .imageToHEIC: "Image -> HEIC"
        case .imageToWebP: "Image -> WebP"
        case .compressZip: "Compress ZIP"
        case .extractZip: "Extract ZIP"
        case .optimizeImages: "Optimize Images"
        case .optimizePDFKeepText: "Optimize PDF"
        case .resizeImages: "Resize Images"
        case .sendToWorkbench: "Send to Workbench"
        case .moveToTrash: "Move to Trash"
        }
    }

    var symbolName: String {
        switch self {
        case .imageToPDF: "photo.on.rectangle.angled"
        case .pdfToImages: "doc.on.doc"
        case .officeToPDF: "doc.richtext"
        case .textDocumentToPDF: "text.document"
        case .imageToJPEG: "photo"
        case .imageToPNG: "photo.stack"
        case .imageToHEIC: "sparkles.tv"
        case .imageToWebP: "globe"
        case .compressZip: "archivebox"
        case .extractZip: "tray.and.arrow.down"
        case .optimizeImages: "wand.and.stars"
        case .optimizePDFKeepText: "doc.text.magnifyingglass"
        case .resizeImages: "arrow.up.left.and.arrow.down.right"
        case .sendToWorkbench: "shippingbox"
        case .moveToTrash: "trash"
        }
    }

    var category: WorkActionCategory {
        switch self {
        case .imageToPDF, .pdfToImages, .officeToPDF, .textDocumentToPDF, .imageToJPEG, .imageToPNG, .imageToHEIC, .imageToWebP:
            return .convert
        case .compressZip, .extractZip, .optimizeImages, .optimizePDFKeepText, .resizeImages:
            return .compress
        case .sendToWorkbench, .moveToTrash:
            return .organize
        }
    }
}

enum DropContentKind: Equatable {
    case images
    case pdfs
    case textDocuments
    case officeDocuments
    case zipArchives
    case mixed
    case unsupported
}

enum WorkActionCategory: String, CaseIterable, Identifiable {
    case convert
    case compress
    case organize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .compress: "Compress"
        case .organize: "Organize"
        }
    }
}

struct DropPlan: Equatable {
    let kind: DropContentKind
    let recommendedAction: WorkActionKind?
    let secondaryActions: [WorkActionKind]
}

struct UndoToken: Equatable {
    let operationID: String
    let sourceURLs: [URL]
    let trashedURLs: [URL]
    let generatedURLs: [URL]
    let expiresAt: Date
}

struct DropExecutionResult: Equatable {
    let action: WorkActionKind
    let outputs: [URL]
    let reclaimedBytes: Int64
    let undoToken: UndoToken?
    let message: String
    let warnings: [String]
}

struct OverlayToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

struct OverlayPerfSnapshot: Equatable {
    var idleCPUPercent: Double
    var triggerFlaps: Int
    var avgDragFrameMs: Double
    var dragSampleCount: Int

    static let empty = OverlayPerfSnapshot(
        idleCPUPercent: 0,
        triggerFlaps: 0,
        avgDragFrameMs: 0,
        dragSampleCount: 0
    )
}

struct NotchLayoutSnapshot: Equatable {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let triggerFrame: CGRect
    let triggerOuterFrame: CGRect
}

protocol WorkActionExecuting: AnyObject {
    func classify(_ inputs: [URL]) -> DropPlan
    func execute(_ action: WorkActionKind, inputs: [URL]) async throws -> DropExecutionResult
    func undo(_ token: UndoToken) async -> Bool
    func unavailableReason(for action: WorkActionKind) -> String?
}

protocol NotchGeometryCalculating: AnyObject {
    func layoutSnapshot(screen: NSScreen) -> NotchLayoutSnapshot
    func panelFrame(screen: NSScreen, panelSize: CGSize) -> CGRect
}

protocol DropRoutingProviding: AnyObject {
    func resolveAction(plan: DropPlan, targeted: WorkActionKind?, telemetry: DropTelemetry?) -> WorkActionKind?
}

protocol TriggerProviding: AnyObject {
    var state: TriggerState { get }
    func update(rawInside: Bool, timestamp: TimeInterval) -> OverlayEvent?
    func reset()
}

protocol DragPipelining: AnyObject {
    func ingest(point: CGPoint, timestamp: TimeInterval) -> DropTelemetry
    func reset()
}

extension WorkActionKind {
    var acceptedTypes: [UTType] {
        switch self {
        case .imageToPDF, .imageToJPEG, .imageToPNG, .imageToHEIC, .imageToWebP, .optimizeImages, .resizeImages:
            [.image]
        case .pdfToImages, .optimizePDFKeepText:
            [.pdf]
        case .officeToPDF, .textDocumentToPDF:
            [.data]
        case .extractZip:
            [.zip]
        case .compressZip, .sendToWorkbench, .moveToTrash:
            [.data]
        }
    }
}

extension WorkActionKind {
    var movesOriginalsToTrash: Bool {
        switch self {
        case .compressZip, .optimizeImages, .optimizePDFKeepText, .resizeImages, .moveToTrash:
            return true
        default:
            return false
        }
    }
}
