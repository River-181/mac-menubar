import CoreGraphics
import Foundation

struct MagnetConfig: Equatable {
    var radius: CGFloat = 110
    var snapThreshold: CGFloat = 60
}

final class WorkspacePhysics {
    let config: MagnetConfig

    init(config: MagnetConfig = MagnetConfig()) {
        self.config = config
    }

    func attractionStrength(distance: CGFloat) -> CGFloat {
        let d = max(0, distance)
        if d > config.radius { return 0 }
        if d <= config.snapThreshold { return 1 }
        let normalized = 1 - ((d - config.snapThreshold) / (config.radius - config.snapThreshold))
        return normalized * normalized
    }

    func shouldSnap(distance: CGFloat) -> Bool {
        distance <= config.snapThreshold
    }

    func orbitRadius(for itemIndex: Int) -> CGFloat {
        let ring = itemIndex / 8
        switch ring {
        case 0: return 72
        case 1: return 112
        default: return 152
        }
    }
}
