import Foundation

final class DropRoutingEngine: DropRoutingProviding {
    func resolveAction(plan: DropPlan, targeted: WorkActionKind?, telemetry: DropTelemetry?) -> WorkActionKind? {
        _ = telemetry
        if let targeted {
            return targeted
        }
        if let recommended = plan.recommendedAction {
            return recommended
        }
        guard !plan.secondaryActions.isEmpty else { return nil }
        return plan.secondaryActions.first
    }
}
