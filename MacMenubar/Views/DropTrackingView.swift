import AppKit
import SwiftUI

struct DropTrackingView: NSViewRepresentable {
    var onDragEntered: ([URL]) -> Void
    var onDragUpdated: (CGPoint) -> Void
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
    var onDragUpdated: ((CGPoint) -> Void)?
    var onDragExited: (() -> Void)?
    var onPerformDrop: (([URL], CGPoint) -> Void)?

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
        onDragEntered?(urls)
        onDragUpdated?(localPoint(from: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        onDragUpdated?(localPoint(from: sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onPerformDrop?(urls, localPoint(from: sender))
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
}
