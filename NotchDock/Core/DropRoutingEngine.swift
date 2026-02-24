import Foundation

final class DropRoutingEngine: DropRoutingProviding {
    func resolveAction(plan: DropPlan, targeted: WorkActionKind?, telemetry: DropTelemetry?) -> WorkActionKind? {
        if let targeted {
            return targeted
        }
        if let recommended = plan.recommendedAction {
            return recommended
        }
        guard !plan.secondaryActions.isEmpty else { return nil }
        if let telemetry, abs(telemetry.velocity.dx) > 850 {
            return telemetry.velocity.dx > 0 ? plan.secondaryActions.first : plan.secondaryActions.last
        }
        return plan.secondaryActions.first
    }
}
