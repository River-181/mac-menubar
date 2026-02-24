import Foundation

struct OverlayStateMachine {
    func reduce(state: OverlayState, event: OverlayEvent, isDragging: Bool) -> OverlayState {
        switch (state, event) {
        case (.hidden, .pointerEnterTrigger):
            return .peek
        case (.armed, .pointerEnterTrigger):
            return .peek
        case (.peek, .clickCapsule):
            return .expand
        case (.expand, .clickCapsule):
            return .peek
        case (.peek, .dragBegan), (.armed, .dragBegan), (.hidden, .dragBegan):
            return .expand
        case (.expand, .dropCommitted):
            return .processing
        case (.processing, .dragEnded):
            return .peek
        case (.peek, .pointerExitTrigger):
            return isDragging ? .peek : .hidden
        case (.expand, .pointerExitTrigger):
            return isDragging ? .expand : .peek
        case (_, .esc):
            switch state {
            case .expand, .processing:
                return .peek
            case .peek, .armed:
                return .hidden
            case .hidden:
                return .hidden
            }
        case (_, .dragEnded):
            if state == .processing {
                return .peek
            }
            return state
        default:
            return state
        }
    }
}
