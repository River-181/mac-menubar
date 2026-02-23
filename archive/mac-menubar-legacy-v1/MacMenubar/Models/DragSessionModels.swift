import CoreGraphics
import Foundation

struct DragSessionContext: Equatable {
    var isFileDrag: Bool
    var hoveredAction: NotchActionKind?
    var enteredAt: Date?

    static let idle = DragSessionContext(isFileDrag: false, hoveredAction: nil, enteredAt: nil)
}

struct DragDynamics: Equatable {
    var velocity: CGPoint
    var acceleration: CGPoint
    var lastPoint: CGPoint
    var lastTimestamp: TimeInterval

    static let zero = DragDynamics(
        velocity: .zero,
        acceleration: .zero,
        lastPoint: .zero,
        lastTimestamp: 0
    )

    var speed: CGFloat {
        sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
    }
}

struct MotionPreferences: Equatable {
    var reduceMotion: Bool
    var subtleMode: Bool
}
