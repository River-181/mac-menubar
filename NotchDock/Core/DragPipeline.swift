import AppKit
import Foundation

final class DragPipeline: DragPipelining {
    private var lastPoint: CGPoint?
    private var lastTimestamp: TimeInterval?

    func ingest(point: CGPoint, timestamp: TimeInterval) -> DropTelemetry {
        defer {
            lastPoint = point
            lastTimestamp = timestamp
        }
        guard let lastPoint, let lastTimestamp else {
            return DropTelemetry(point: point, velocity: .zero, timestamp: timestamp)
        }
        let delta = max(0.0001, timestamp - lastTimestamp)
        let velocity = CGVector(dx: (point.x - lastPoint.x) / delta, dy: (point.y - lastPoint.y) / delta)
        return DropTelemetry(point: point, velocity: velocity, timestamp: timestamp)
    }

    func reset() {
        lastPoint = nil
        lastTimestamp = nil
    }
}
