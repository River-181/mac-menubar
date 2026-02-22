import AppKit
import SwiftUI

struct DropTrackingView: NSViewRepresentable {
    var onDragEntered: ([URL]) -> Void
    var onDragUpdated: (CGPoint, DragDynamics) -> Void
    var onDragExited: () -> Void
    var onPerformDrop: ([URL], CGPoint) -> Void

    func makeNSView(context: Context) -> DropTrackingNSView {
        let view = DropTrackingNSView()
        view.onDragEntered = onDragEntered
        view.onDragUpdated = onDragUpdated
        view.onDragExited = onDragExited
        view.onPerformDrop = onPerformDrop
        return view
    }

    func updateNSView(_ nsView: DropTrackingNSView, context: Context) {
        nsView.onDragEntered = onDragEntered
        nsView.onDragUpdated = onDragUpdated
        nsView.onDragExited = onDragExited
        nsView.onPerformDrop = onPerformDrop
    }
}

final class DropTrackingNSView: NSView {
    var onDragEntered: (([URL]) -> Void)?
    var onDragUpdated: ((CGPoint, DragDynamics) -> Void)?
    var onDragExited: (() -> Void)?
    var onPerformDrop: (([URL], CGPoint) -> Void)?
    private var currentDragURLs: [URL] = []
    private var hasActiveFileDrag = false
    private var lastReportedPoint: CGPoint = .zero
    private var lastReportedTime: CFTimeInterval = 0
    private var lastVelocity: CGPoint = .zero
    private let minimumUpdateInterval: CFTimeInterval = 1.0 / 30.0
    private let minimumPointDelta: CGFloat = 1.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        currentDragURLs = urls
        hasActiveFileDrag = true
        onDragEntered?(urls)
        let point = localPoint(from: sender)
        lastReportedPoint = point
        lastReportedTime = CACurrentMediaTime()
        lastVelocity = .zero
        onDragUpdated?(
            point,
            DragDynamics(
                velocity: .zero,
                acceleration: .zero,
                lastPoint: point,
                lastTimestamp: lastReportedTime
            )
        )
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasActiveFileDrag else { return [] }
        let point = localPoint(from: sender)
        let now = CACurrentMediaTime()
        let movedEnough = abs(point.x - lastReportedPoint.x) >= minimumPointDelta || abs(point.y - lastReportedPoint.y) >= minimumPointDelta
        let elapsedEnough = now - lastReportedTime >= minimumUpdateInterval
        if movedEnough && elapsedEnough {
            let dt = max(0.0001, now - lastReportedTime)
            let velocity = CGPoint(
                x: (point.x - lastReportedPoint.x) / dt,
                y: (point.y - lastReportedPoint.y) / dt
            )
            let acceleration = CGPoint(
                x: (velocity.x - lastVelocity.x) / dt,
                y: (velocity.y - lastVelocity.y) / dt
            )
            lastVelocity = velocity
            lastReportedPoint = point
            lastReportedTime = now
            onDragUpdated?(
                point,
                DragDynamics(
                    velocity: velocity,
                    acceleration: acceleration,
                    lastPoint: point,
                    lastTimestamp: now
                )
            )
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        resetDragState()
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasActiveFileDrag || !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = currentDragURLs.isEmpty ? fileURLs(from: sender) : currentDragURLs
        guard !urls.isEmpty else { return false }
        let point = localPoint(from: sender)
        onPerformDrop?(urls, point)
        resetDragState()
        return true
    }

    private func localPoint(from sender: NSDraggingInfo) -> CGPoint {
        let pointInWindow = sender.draggingLocation
        return convert(pointInWindow, from: nil)
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])?
            .compactMap { $0 as? URL } ?? []
    }

    private func resetDragState() {
        hasActiveFileDrag = false
        currentDragURLs = []
        lastVelocity = .zero
        lastReportedPoint = .zero
        lastReportedTime = 0
    }
}
