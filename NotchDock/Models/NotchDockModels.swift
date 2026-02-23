import AppKit
import ApplicationServices
import Combine
import Foundation
import UniformTypeIdentifiers

enum DockOverlayState: String, Codable, Equatable {
    case idle
    case peek
    case expand
    case grab
    case focus
    case workspace
}

extension DockOverlayState {
    var capsuleSize: CGSize {
        switch self {
        case .idle:
            return CGSize(width: 170, height: 36)
        case .peek:
            return CGSize(width: 320, height: 58)
        case .expand, .grab, .focus:
            return CGSize(width: 620, height: 248)
        case .workspace:
            return CGSize(width: 780, height: 312)
        }
    }

    var panelFrameSize: CGSize {
        let capsule = capsuleSize
        return CGSize(width: capsule.width + 16, height: capsule.height + 20)
    }
}

enum OverlayEvent: Equatable {
    case topTriggerEnter
    case topTriggerExit
    case capsuleClick
    case pointerLeave
    case pointerReturn
    case stage2(Stage2Trigger)
    case closeOneLevel
    case longPressIcon(String)
    case focusIcon(String)
    case closeFocus
}

enum Stage2Trigger: String, Codable, CaseIterable, Equatable {
    case forceClick
    case dwell300ms
    case doubleClick
    case hotkey
    case dragHover250ms
}

enum PointerSamplingMode: String, Codable, Equatable {
    case idle
    case armed
    case drag
}

enum TriggerState: String, Codable, Equatable {
    case outside
    case entering
    case inside
    case exiting
}

struct DragTelemetry: Equatable {
    var point: CGPoint
    var velocity: CGVector
    var timestamp: TimeInterval
}

struct OverlayPerfSnapshot: Equatable {
    var idleCPU: Double
    var triggerFlaps: Int
    var avgDragFrameMs: Double
    var stateTransitions: Int

    static let empty = OverlayPerfSnapshot(
        idleCPU: 0,
        triggerFlaps: 0,
        avgDragFrameMs: 0,
        stateTransitions: 0
    )
}

enum NotchDefaultPolicy: String, Codable, CaseIterable, Identifiable {
    case adaptiveAuto
    case alwaysCompact
    case alwaysRespect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptiveAuto: return "Adaptive Auto"
        case .alwaysCompact: return "Always Compact"
        case .alwaysRespect: return "Always Respect"
        }
    }
}

enum WorkHubStyle: String, Codable, CaseIterable, Identifiable {
    case magneticDock

    var id: String { rawValue }
}

enum IconBucket: String, Codable, CaseIterable, Equatable {
    case pinned
    case shelf
    case overflow
}

enum IconSourceKind: String, Codable, Equatable {
    case manual
    case ax
}

struct DockIcon: Identifiable, Hashable {
    let id: String
    var source: IconSourceKind
    var symbolOrImage: String
    var iconData: Data? = nil
    var title: String
    var bucket: IconBucket
    var groupID: String
    var lastUsedAt: Date
    var rank: Double
}

struct DropTarget: Identifiable, Equatable {
    let action: WorkActionKind
    let title: String
    let accepts: [UTType]

    var id: String { action.rawValue }
}

enum WorkActionKind: String, Codable, CaseIterable, Identifiable {
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
        case .imageToPDF: return "Image -> PDF"
        case .pdfToImages: return "PDF -> Images"
        case .compressZip: return "Compress ZIP"
        case .extractZip: return "Extract ZIP"
        case .optimizeImages: return "Optimize Images"
        case .optimizePDFKeepText: return "Optimize PDF"
        case .resizeImages: return "Resize Images"
        case .sendToWorkbench: return "Send to Workbench"
        case .moveToTrash: return "Move to Trash"
        }
    }

    var symbolName: String {
        switch self {
        case .imageToPDF: return "photo.on.rectangle.angled"
        case .pdfToImages: return "doc.on.doc"
        case .compressZip: return "archivebox"
        case .extractZip: return "tray.and.arrow.down"
        case .optimizeImages: return "wand.and.stars"
        case .optimizePDFKeepText: return "doc.text.magnifyingglass"
        case .resizeImages: return "arrow.up.left.and.arrow.down.right"
        case .sendToWorkbench: return "shippingbox"
        case .moveToTrash: return "trash"
        }
    }
}

enum DropContentKind: String, Equatable {
    case images
    case pdfs
    case zipArchives
    case mixed
    case unsupported
}

enum FileOutputPolicy: Equatable {
    case datedFolder
}

struct DropPlan: Equatable {
    let kind: DropContentKind
    let recommendedAction: WorkActionKind?
    let secondaryActions: [WorkActionKind]
}

enum DangerousOperationKind: String, Codable, Equatable {
    case moveToTrash
    case compressAndTrashOriginals
    case replaceWithOptimized
}

struct UndoReplacement: Equatable {
    let sourceURL: URL
    let generatedURL: URL
}

struct UndoToken: Equatable {
    let operationID: String
    let operationKind: DangerousOperationKind
    let sourceURLs: [URL]
    let destinationURLs: [URL]
    let replacements: [UndoReplacement]
    let createdAt: Date
    let expiresAt: Date
}

struct ActionExecutionResult: Equatable {
    let action: WorkActionKind
    let outputs: [URL]
    let reclaimedBytes: Int64
    let message: String
    let undoToken: UndoToken?
    let warnings: [String]
}

struct WorkspaceCard: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var fileURL: URL?
    var noteText: String?
    var positionX: Double
    var positionY: Double
    var clusterID: String?
}

struct WorkspaceCluster: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var colorHex: String
}

struct WorkspaceState: Codable, Equatable {
    var cards: [WorkspaceCard]
    var clusters: [WorkspaceCluster]
    var updatedAt: Date

    static let empty = WorkspaceState(cards: [], clusters: [], updatedAt: .distantPast)
}

struct DropToast: Equatable {
    let message: String
    let isError: Bool
}

struct NotchLayoutSnapshot: Equatable {
    var screenWidth: CGFloat
    var safeLeft: CGFloat
    var safeRight: CGFloat
    var hasNotch: Bool
    var compactMode: Bool
    var spacing: CGFloat
}

enum MirrorAuthState: String, Codable, Equatable {
    case unknown
    case denied
    case granted
}

struct ExternalMenuBarItem: Identifiable, Equatable {
    let id: String
    var ownerBundleID: String
    var title: String
    var frameInScreen: CGRect
    var supportsPressAction: Bool
    var imageData: Data?
}

protocol IconSourceProviding: AnyObject {
    func fetchIcons() async -> [DockIcon]
}

@MainActor
protocol RunningAppIconControlling: AnyObject {
    func setIncludeRunningApps(_ enabled: Bool)
}

protocol WorkActionExecuting: AnyObject {
    func classify(_ urls: [URL]) -> DropPlan
    func execute(action: WorkActionKind, inputs: [URL], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult
    func undo(token: UndoToken) -> Bool
}

protocol NotchGeometryCalculating: AnyObject {
    func capsuleFrame(screen: NSScreen, state: DockOverlayState, policy: NotchDefaultPolicy) -> CGRect
    func capsuleFrame(screen: NSScreen, visualState: DockOverlayState, policy: NotchDefaultPolicy, compactOverride: Bool?) -> CGRect
    func triggerZone(screen: NSScreen) -> CGRect
    func hitMaskRect(for state: DockOverlayState, panelFrame: CGRect) -> CGRect
    func layoutSnapshot(screen: NSScreen, policy: NotchDefaultPolicy) -> NotchLayoutSnapshot
}

protocol WorkspaceStoring: AnyObject {
    func load() -> WorkspaceState
    func save(_ state: WorkspaceState) throws
}

@MainActor
protocol ExternalIconProviding: AnyObject {
    var itemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> { get }
    var authState: MirrorAuthState { get }
    func start()
    func refresh()
    func setHighFrequencyMode(_ enabled: Bool)
}

extension ExternalIconProviding {
    func setHighFrequencyMode(_ enabled: Bool) {
        _ = enabled
    }
}
