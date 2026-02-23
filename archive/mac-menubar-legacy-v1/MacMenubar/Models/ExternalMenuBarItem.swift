import ApplicationServices
import Combine
import CoreGraphics
import Foundation

enum MirrorAuthState: String, Codable, Equatable {
    case unknown
    case denied
    case granted
}

enum ExternalItemVisibilityMode: String, Codable, CaseIterable, Identifiable {
    case mirrorOnly
    case mirrorAndHide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mirrorOnly:
            return "Mirror only"
        case .mirrorAndHide:
            return "Mirror + Hide"
        }
    }
}

enum ExternalHideFailureReason: String, Codable, Equatable {
    case unsupportedAttribute
    case permissionDenied
    case actionFailed
}

enum ExternalShelfState: String, Codable, Equatable {
    case none
    case hidden
    case staleHidden
}

struct ExternalMenuBarItem: Identifiable, Equatable {
    let id: String
    var ownerBundleID: String
    var displayName: String
    var frameInScreen: CGRect
    var isVisibleInSystemBar: Bool
    var supportsPressAction: Bool
    var iconPNGData: Data?
    var lastSeenAt: Date
    var lastInteractionAt: Date
    var shelfState: ExternalShelfState

    var estimatedWidth: CGFloat {
        max(22, min(56, frameInScreen.width + 8))
    }
}

struct ExternalIconPreference: Codable, Equatable {
    var mode: ExternalItemVisibilityMode
    var userPinned: Bool
    var hiddenEnabled: Bool
    var downgradeReason: ExternalHideFailureReason?

    static let `default` = ExternalIconPreference(
        mode: .mirrorOnly,
        userPinned: false,
        hiddenEnabled: false,
        downgradeReason: nil
    )
}

struct ExternalModeUpdateResult: Equatable {
    var effectiveMode: ExternalItemVisibilityMode
    var downgradeReason: ExternalHideFailureReason?
}

@MainActor
protocol ExternalMenuBarProviding: AnyObject {
    var externalItemsPublisher: AnyPublisher<[ExternalMenuBarItem], Never> { get }
    var hiddenShelfPublisher: AnyPublisher<[ExternalMenuBarItem], Never> { get }
    func start()
    func stop()
    func refresh()
    func setVisibilityMode(_ mode: ExternalItemVisibilityMode, for itemID: String) -> ExternalModeUpdateResult
    func revealHiddenItem(_ itemID: String) -> Bool
    func performPrimaryAction(for itemID: String) -> Bool
    func currentAuthState() -> MirrorAuthState
    func requestPermission() -> MirrorAuthState
    func openSystemSettings()
}

protocol AXPermissionProviding: AnyObject {
    func currentState() -> MirrorAuthState
    func requestPermission() -> MirrorAuthState
    func openAccessibilitySettings()
}

protocol AXActionBridging: AnyObject {
    func performPrimaryAction(on element: AXUIElement, fallbackFrame: CGRect?) -> Bool
    func performFallbackClick(frame: CGRect) -> Bool
    func setHidden(_ hidden: Bool, for element: AXUIElement) -> ExternalHideFailureReason?
}
