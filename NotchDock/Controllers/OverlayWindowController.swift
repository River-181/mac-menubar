import AppKit
import Combine
import Darwin
import os.signpost
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OverlayWindowController {
    private let viewModel: NotchDockViewModel
    private let geometry: NotchGeometryCalculating
    private let panel: NSPanel
    private let dragPipeline: DragPipelining
    private let hitMask = HitMaskEngine()

    private var samplingMode: PointerSamplingMode = .armed
    private var samplingTimer: Timer?
    private var stateObserver: AnyCancellable?
    private var perfTimer: Timer?
    private var lastCPUSample: (cpuSeconds: Double, wall: TimeInterval)?
    private var dragDetectedUntil: TimeInterval = 0
    private let signpostLog = OSLog(subsystem: "com.river.notchdock", category: "overlay")

    init(
        viewModel: NotchDockViewModel,
        geometry: NotchGeometryCalculating = NotchGeometryCalculator(),
        dragPipeline: DragPipelining = DragPipeline()
    ) {
        self.viewModel = viewModel
        self.geometry = geometry
        self.dragPipeline = dragPipeline

        let initialSize = viewModel.panelSize
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: OverlayRootView(viewModel: viewModel))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = OverlayPassThroughContainerView(
            frame: panel.contentRect(forFrameRect: panel.frame)
        ) { [weak self] pointInWindow in
            guard let self else { return false }
            guard !self.panel.ignoresMouseEvents else { return false }
            let screenPoint = self.panel.convertToScreen(
                NSRect(origin: pointInWindow, size: .zero)
            ).origin
            guard let screen = self.panel.screen ?? NSScreen.main else { return false }
            let snapshot = self.geometry.layoutSnapshot(screen: screen)
            return self.hitMask.isInsideCapsule(
                point: screenPoint,
                panelFrame: self.panel.frame,
                state: self.viewModel.presentationState,
                hasNotch: snapshot.hasNotch,
                notchWidth: snapshot.notchWidth
            )
        }
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container
        panel.orderFrontRegardless()

        stateObserver = viewModel.$panelSize
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.layoutPanel()
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        setSamplingMode(.armed)
        startPerfSampling()
        layoutPanel()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        samplingTimer?.invalidate()
        perfTimer?.invalidate()
    }

    func toggleExpand() {
        viewModel.toggleExpand()
    }

    @objc private func handleScreenChanged() {
        layoutPanel()
    }

    private func layoutPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = geometry.panelFrame(screen: screen, panelSize: viewModel.panelSize)
        if !panel.frame.equalTo(frame) {
            panel.setFrame(frame, display: false)
        }
    }

    private func setSamplingMode(_ mode: PointerSamplingMode) {
        guard samplingMode != mode else { return }
        samplingMode = mode
        recordPerfSignpost("sampling.\(mode.rawValue)")
        rebuildTrackingPipelineIfNeeded()
    }

    private func rebuildTrackingPipelineIfNeeded() {
        let interval = intervalForSamplingMode(samplingMode)
        samplingTimer?.invalidate()
        samplingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sample()
            }
        }
        samplingTimer?.tolerance = max(0.01, interval * 0.35)
    }

    private func sample() {
        let now = Date().timeIntervalSinceReferenceDate
        let point = NSEvent.mouseLocation
        let screen = screenContaining(point: point)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let telemetry = dragPipeline.ingest(point: point, timestamp: now)
        let snapshot = geometry.layoutSnapshot(screen: screen)

        let isFileDrag = isFileDragInProgress(now: now)
        let isCapsuleInside = hitMask.isInsideCapsule(
            point: point,
            panelFrame: panel.frame,
            state: viewModel.presentationState,
            hasNotch: snapshot.hasNotch,
            notchWidth: snapshot.notchWidth
        )
        let isTriggerInside = snapshot.triggerFrame.contains(point)
        let isOuterInside = snapshot.triggerOuterFrame.contains(point)
        let isActivationTrigger = isTriggerInside || (isOuterInside && isFileDrag && viewModel.overlayState != .hidden)

        let shouldIntercept = isCapsuleInside || isActivationTrigger
        panel.ignoresMouseEvents = !shouldIntercept

        viewModel.ingestPointerSample(
            telemetry,
            isTriggerRawInside: isTriggerInside,
            isTriggerOuterInside: isOuterInside,
            isCapsuleInside: isCapsuleInside,
            isDragging: isFileDrag
        )

        if isFileDrag {
            setSamplingMode(.drag)
        } else if isOuterInside || viewModel.overlayState != .hidden {
            setSamplingMode(.armed)
        } else {
            setSamplingMode(.idle)
            dragPipeline.reset()
        }
    }

    private func isFileDragInProgress(now: TimeInterval) -> Bool {
        let dragPasteboard = NSPasteboard(name: .drag)
        let canReadURL = dragPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        let hasTypeHint = hasFileDragType(in: dragPasteboard)
        let detected = canReadURL || hasTypeHint
        if detected {
            dragDetectedUntil = now + 0.20
            return true
        }
        return now <= dragDetectedUntil
    }

    private func hasFileDragType(in pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let rawTypes = Set(types.map(\.rawValue))
        let hints: [String] = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            UTType.fileURL.identifier,
            "NSFilenamesPboardType",
            "public.url",
            "com.apple.pasteboard.promised-file-url"
        ]
        return hints.contains(where: rawTypes.contains)
    }

    private func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSPointInRect(point, $0.frame) })
    }

    private func intervalForSamplingMode(_ mode: PointerSamplingMode) -> TimeInterval {
        switch mode {
        case .idle:
            0.18
        case .armed:
            0.06
        case .drag:
            0.03
        }
    }

    func recordPerfSignpost(_ name: String) {
        os_signpost(.event, log: signpostLog, name: "Overlay", "%{public}s", name)
    }

    private func startPerfSampling() {
        perfTimer?.invalidate()
        perfTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sampleIdleCPU()
            }
        }
        perfTimer?.tolerance = 0.5
    }

    private func sampleIdleCPU() {
        guard viewModel.overlayState == .hidden else {
            lastCPUSample = nil
            return
        }
        guard let cpu = currentCPUSeconds() else { return }
        let now = Date().timeIntervalSinceReferenceDate
        defer { lastCPUSample = (cpu, now) }
        guard let last = lastCPUSample else { return }
        let wallDelta = max(0.001, now - last.wall)
        let cpuDelta = max(0, cpu - last.cpuSeconds)
        let percent = (cpuDelta / wallDelta) * 100
        viewModel.updateIdleCPU(percent: percent)
        if percent > 4.5 {
            recordPerfSignpost("idleCPU.high.\(percent)")
        }
    }

    private func currentCPUSeconds() -> Double? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
    }
}

enum PointerSamplingMode: String {
    case idle
    case armed
    case drag
}

private final class OverlayPassThroughContainerView: NSView {
    private let shouldHandlePoint: (CGPoint) -> Bool

    init(frame: CGRect, shouldHandlePoint: @escaping (CGPoint) -> Bool) {
        self.shouldHandlePoint = shouldHandlePoint
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldHandlePoint(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}
