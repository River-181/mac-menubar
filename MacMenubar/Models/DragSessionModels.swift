import Foundation

struct DragSessionContext: Equatable {
    var isFileDrag: Bool
    var hoveredAction: NotchActionKind?
    var enteredAt: Date?

    static let idle = DragSessionContext(isFileDrag: false, hoveredAction: nil, enteredAt: nil)
}
