import AppKit
import Foundation
@testable import NotchDock

final class TestIconSource: IconSourceProviding {
    var icons: [DockIcon]

    init(icons: [DockIcon] = []) {
        self.icons = icons
    }

    func fetchIcons() async -> [DockIcon] {
        icons
    }
}

final class TestWorkActionService: WorkActionExecuting {
    var plan = DropPlan(kind: .unsupported, recommendedAction: nil, secondaryActions: [])
    var lastExecutedAction: WorkActionKind?
    var executionResult = ActionExecutionResult(
        action: .sendToWorkbench,
        outputs: [],
        reclaimedBytes: 0,
        message: "OK",
        undoToken: nil,
        warnings: []
    )
    var shouldThrow = false
    var undoReturnValue = true

    func classify(_ urls: [URL]) -> DropPlan {
        plan
    }

    func execute(action: WorkActionKind, inputs: [URL], outputPolicy: FileOutputPolicy) throws -> ActionExecutionResult {
        _ = inputs
        _ = outputPolicy
        lastExecutedAction = action
        if shouldThrow {
            throw WorkActionError.commandFailed("forced")
        }
        var result = executionResult
        result = ActionExecutionResult(
            action: action,
            outputs: executionResult.outputs,
            reclaimedBytes: executionResult.reclaimedBytes,
            message: executionResult.message,
            undoToken: executionResult.undoToken,
            warnings: executionResult.warnings
        )
        return result
    }

    func undo(token: UndoToken) -> Bool {
        _ = token
        return undoReturnValue
    }
}

final class TestGeometry: NotchGeometryCalculating {
    func capsuleFrame(screen: NSScreen, state: DockOverlayState, policy: NotchDefaultPolicy) -> CGRect {
        _ = state
        _ = policy
        return CGRect(x: screen.visibleFrame.midX - 490, y: screen.visibleFrame.maxY - 320, width: 980, height: 320)
    }

    func capsuleFrame(screen: NSScreen, visualState: DockOverlayState, policy: NotchDefaultPolicy, compactOverride: Bool?) -> CGRect {
        _ = visualState
        _ = policy
        _ = compactOverride
        return CGRect(x: screen.visibleFrame.midX - 490, y: screen.visibleFrame.maxY - 320, width: 980, height: 320)
    }

    func triggerZone(screen: NSScreen) -> CGRect {
        CGRect(x: screen.visibleFrame.midX - 110, y: screen.visibleFrame.maxY - 16, width: 220, height: 16)
    }

    func hitMaskRect(for state: DockOverlayState, panelFrame: CGRect) -> CGRect {
        _ = state
        return panelFrame.insetBy(dx: 8, dy: 8)
    }

    func layoutSnapshot(screen: NSScreen, policy: NotchDefaultPolicy) -> NotchLayoutSnapshot {
        _ = policy
        return NotchLayoutSnapshot(
            screenWidth: screen.frame.width,
            safeLeft: 0,
            safeRight: 0,
            hasNotch: false,
            compactMode: false,
            spacing: 8
        )
    }
}

final class TestWorkspaceStore: WorkspaceStoring {
    var state: WorkspaceState = .empty

    func load() -> WorkspaceState {
        state
    }

    func save(_ state: WorkspaceState) throws {
        self.state = state
    }
}
