import AppKit
import Combine
import Darwin
import os.signpost
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let viewModel: NotchDockViewModel
    private let geometry: NotchGeometryCalculating
    private let panel: NSPanel
    private var trackingTimer: Timer?
    private var perfTimer: Timer?
    private var localKeyMonitor: Any?
    private var policyObserver: AnyCancellable?
    private var lastMouseLocation: CGPoint?
    private var lastSampleTimestamp: TimeInterval?
    private var panelInteractionEnabled = false
    private var samplingMode: PointerSamplingMode = .armed
    private var samplingInterval: TimeInterval = 0.06
    private let signpostLog = OSLog(subsystem: "com.river.notchdock", category: "overlay")
    private var lastCPUSample: (cpuSeconds: Double, wallTime: TimeInterval)?

    init(viewModel: NotchDockViewModel, geometry: NotchGeometryCalculating = NotchGeometryCalculator()) {
        self.viewModel = viewModel
        self.geometry = geometry

        let initialSize = DockOverlayState.workspace.panelFrameSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
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
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true

        let hostingView = NSHostingView(rootView: OverlayRootView(viewModel: viewModel))
        hostingView.frame = panel.contentRect(forFrameRect: panel.frame)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = hostingView
        self.panel = panel

        layoutPanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        policyObserver = viewModel.$notchDefaultPolicy
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.layoutPanel()
            }

        setSamplingMode(.idle)
        startPerfSampling()
        installKeyMonitor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        trackingTimer?.invalidate()
        perfTimer?.invalidate()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    @objc private func handleScreenChange() {
        layoutPanel()
    }

    func layoutPanel() {
        guard let screen = NSScreen.main else { return }
        // Keep a stable panel frame and animate content inside SwiftUI.
        // This avoids AppKit update-constraints loops from rapid frame mutation.
        let frame = geometry.capsuleFrame(
            screen: screen,
            visualState: .workspace,
            policy: viewModel.notchDefaultPolicy,
            compactOverride: nil
        )
        if !panel.frame.equalTo(frame) {
            panel.setFrame(frame, display: true)
        }
        viewModel.refreshLayout(for: screen)
    }

    func toggleExpand() {
        viewModel.toggleExpand()
    }

    func setSamplingMode(_ mode: PointerSamplingMode) {
        guard samplingMode != mode else { return }
        samplingMode = mode
        recordPerfSignpost("sampling.\(mode.rawValue)")
        rebuildTrackingPipelineIfNeeded()
    }

    func rebuildTrackingPipelineIfNeeded() {
        let nextInterval = interval(for: samplingMode)
        if abs(nextInterval - samplingInterval) < 0.001, trackingTimer != nil {
            return
        }
        samplingInterval = nextInterval
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: nextInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sampleTopTrigger()
            }
        }
        trackingTimer?.tolerance = max(0.01, nextInterval * 0.35)
    }

    private func sampleTopTrigger() {
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let timestamp = Date().timeIntervalSinceReferenceDate
        let velocity = computeVelocity(for: mouse, timestamp: timestamp)
        let distance: CGFloat
        if let lastMouseLocation {
            distance = hypot(mouse.x - lastMouseLocation.x, mouse.y - lastMouseLocation.y)
        } else {
            distance = .greatestFiniteMagnitude
        }
        let mouseMovedEnough = distance > 1.5
        let dragActive = (NSEvent.pressedMouseButtons & 1) == 1

        if !mouseMovedEnough
            && !dragActive
            && viewModel.overlayState == .idle
            && !viewModel.isNearTopTrigger
            && viewModel.triggerState == .outside {
            setPanelInteractionEnabled(false)
            setSamplingMode(.idle)
            return
        }

        lastMouseLocation = mouse
        let trigger = geometry.triggerZone(screen: screen)
        let insideCapsule = isPointInsideCapsule(mouse)
        let rawInsideTrigger = trigger.contains(mouse)

        // Keep passthrough outside the visual capsule, but allow notch-top drag entry.
        setPanelInteractionEnabled(insideCapsule || rawInsideTrigger)
        viewModel.ingestPointerSample(
            DragTelemetry(point: mouse, velocity: velocity, timestamp: timestamp),
            isTriggerRawInside: rawInsideTrigger,
            isCapsuleInside: insideCapsule,
            isDragging: dragActive
        )

        if dragActive {
            setSamplingMode(.drag)
        } else if insideCapsule || rawInsideTrigger || viewModel.overlayState != .idle || viewModel.triggerState != .outside {
            setSamplingMode(.armed)
        } else {
            setSamplingMode(.idle)
        }
    }

    private func interval(for mode: PointerSamplingMode) -> TimeInterval {
        switch mode {
        case .idle:
            return 0.18
        case .armed:
            return 0.06
        case .drag:
            return 0.03
        }
    }

    private func computeVelocity(for mouse: CGPoint, timestamp: TimeInterval) -> CGVector {
        guard let previousPoint = lastMouseLocation, let previousTimestamp = lastSampleTimestamp else {
            lastSampleTimestamp = timestamp
            return .zero
        }
        let delta = max(0.0001, timestamp - previousTimestamp)
        lastSampleTimestamp = timestamp
        return CGVector(
            dx: (mouse.x - previousPoint.x) / delta,
            dy: (mouse.y - previousPoint.y) / delta
        )
    }

    func recordPerfSignpost(_ name: String) {
        os_signpost(.event, log: signpostLog, name: "OverlayPerf", "%{public}s", name)
    }

    private func startPerfSampling() {
        perfTimer?.invalidate()
        perfTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sampleIdleCPU()
            }
        }
        perfTimer?.tolerance = 0.6
    }

    private func sampleIdleCPU() {
        guard viewModel.overlayState == .idle else {
            return
        }
        guard let cpuSeconds = currentProcessCPUSeconds() else {
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        defer {
            lastCPUSample = (cpuSeconds: cpuSeconds, wallTime: now)
        }
        guard let last = lastCPUSample else {
            return
        }
        let deltaWall = now - last.wallTime
        guard deltaWall > 0 else {
            return
        }
        let deltaCPU = max(0, cpuSeconds - last.cpuSeconds)
        let usagePercent = (deltaCPU / deltaWall) * 100
        viewModel.updateIdleCPU(usagePercent)
    }

    private func currentProcessCPUSeconds() -> Double? {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_THREAD_TIMES_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }

        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
    }

    private func setPanelInteractionEnabled(_ enabled: Bool) {
        guard panelInteractionEnabled != enabled else { return }
        panelInteractionEnabled = enabled
        panel.ignoresMouseEvents = !enabled
    }

    private func isPointInsideCapsule(_ point: CGPoint) -> Bool {
        let capsuleRect = geometry.hitMaskRect(for: viewModel.overlayState, panelFrame: panel.frame)

        if capsuleRect.width <= 0 || capsuleRect.height <= 0 || !capsuleRect.contains(point) {
            return false
        }

        let radius = capsuleRect.height / 2
        let centerBand = CGRect(
            x: capsuleRect.minX + radius,
            y: capsuleRect.minY,
            width: max(0, capsuleRect.width - (radius * 2)),
            height: capsuleRect.height
        )
        if centerBand.contains(point) {
            return true
        }

        let leftCenter = CGPoint(x: capsuleRect.minX + radius, y: capsuleRect.midY)
        let rightCenter = CGPoint(x: capsuleRect.maxX - radius, y: capsuleRect.midY)
        let leftDistance = hypot(point.x - leftCenter.x, point.y - leftCenter.y)
        let rightDistance = hypot(point.x - rightCenter.x, point.y - rightCenter.y)
        return leftDistance <= radius || rightDistance <= radius
    }

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleKey(event) {
                return nil
            }
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let optionPressed = event.modifierFlags.contains(.option)
        switch (event.keyCode, optionPressed) {
        case (49, true): // Option + Space
            viewModel.toggleExpand()
            return true
        case (36, true): // Option + Return
            viewModel.toggleWorkspace(trigger: .hotkey)
            return true
        case (53, _): // Escape
            viewModel.closeOneLevel()
            return true
        case (123, true): // Option + Left
            viewModel.focusPreviousGroup()
            return true
        case (124, true): // Option + Right
            viewModel.focusNextGroup()
            return true
        case (44, true): // Option + /
            return true
        default:
            return false
        }
    }
}
