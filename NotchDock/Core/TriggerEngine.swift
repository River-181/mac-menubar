import Foundation

final class TriggerEngine: TriggerProviding {
    private let enterDelay: TimeInterval
    private let exitDelay: TimeInterval

    private(set) var state: TriggerState = .outside
    private var enterStartedAt: TimeInterval?
    private var exitStartedAt: TimeInterval?

    init(enterDelay: TimeInterval = 0.035, exitDelay: TimeInterval = 0.1) {
        self.enterDelay = enterDelay
        self.exitDelay = exitDelay
    }

    func update(rawInside: Bool, timestamp: TimeInterval) -> OverlayEvent? {
        switch state {
        case .outside:
            if rawInside {
                state = .entering
                enterStartedAt = timestamp
            }
            return nil

        case .entering:
            if !rawInside {
                state = .outside
                enterStartedAt = nil
                return nil
            }
            if timestamp - (enterStartedAt ?? timestamp) >= enterDelay {
                state = .inside
                enterStartedAt = nil
                return .pointerEnterTrigger
            }
            return nil

        case .inside:
            if !rawInside {
                state = .exiting
                exitStartedAt = timestamp
            }
            return nil

        case .exiting:
            if rawInside {
                state = .inside
                exitStartedAt = nil
                return nil
            }
            if timestamp - (exitStartedAt ?? timestamp) >= exitDelay {
                state = .outside
                exitStartedAt = nil
                return .pointerExitTrigger
            }
            return nil
        }
    }

    func reset() {
        state = .outside
        enterStartedAt = nil
        exitStartedAt = nil
    }
}
