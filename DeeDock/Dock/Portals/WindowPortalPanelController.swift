import AppKit
import SwiftUI
import OSLog

private final class WindowPortalPanel: NSPanel {
    var handleKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if handleKey?(event) != true { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the native window and exactly one serial capture loop until close. UI mutation stays on MainActor.
@MainActor
final class WindowPortalPanelController: NSObject, NSWindowDelegate {
    let state: WindowPortalState
    private let panel: WindowPortalPanel
    private let capture: WindowPortalCapture
    private let application: NSRunningApplication?
    private var captureTask: Task<Void, Never>?
    private var freshnessTask: Task<Void, Never>?
    private var jumpTask: Task<Void, Never>?
    private var suspended = false
    private var closed = false
    private var epoch = UUID()
    private var lastSuccess: ContinuousClock.Instant?
    private let started = ContinuousClock.now
    var onClose: (() -> Void)?

    init(source: ApplicationWindowSummary, appName: String, origin: CGPoint) {
        state = WindowPortalState(appName: appName, source: source)
        capture = WindowPortalCapture(source: source)
        application = NSRunningApplication(processIdentifier: source.processIdentifier)
        panel = WindowPortalPanel(contentRect: CGRect(origin: origin, size: CGSize(width: 360, height: 260)),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = state.sourceName
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        // No focus on creation or hover. Clicking or keyboard navigation can deliberately make it key.
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = CGSize(width: 240, height: 160)
        panel.maxSize = CGSize(width: 960, height: 720)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: WindowPortalView(state: state))
        panel.handleKey = { [weak self] in self?.handleKey($0) ?? false }
        state.close = { [weak self] in self?.close() }
        state.jump = { [weak self] in self?.jump() }
        state.togglePause = { [weak self] in self?.togglePause() }
        state.move = { [weak self] x, y in self?.move(x: x, y: y) }
        repairPlacement()
    }

    func show(keyboard: Bool) {
        panel.orderFrontRegardless()
        if keyboard { panel.makeKeyAndOrderFront(nil) }
        captureTask = Task { @MainActor [weak self] in
            defer { self?.captureFinished() }
            while !Task.isCancelled {
                guard let self, !closed else { return }
                await refresh()
                let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 1
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
        // A capture request may take longer than its nominal cadence. Age must advance independently.
        freshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, !closed else { return }
                if state.phase == .live, let lastSuccess, lastSuccess.duration(to: .now) > .seconds(5) {
                    state.phase = .stale
                }
            }
        }
    }

    func focus() { panel.makeKeyAndOrderFront(nil) }

    func setSuspended(_ value: Bool) {
        suspended = value
        epoch = UUID()
        state.phase = .paused
    }

    func repairPlacement() {
        guard let screen = NSScreen.screens.max(by: {
            intersectionArea(panel.frame, $0.visibleFrame) < intersectionArea(panel.frame, $1.visibleFrame)
        }) else { return }
        panel.setFrame(WindowPortalGeometry.clamped(panel.frame, to: screen.visibleFrame), display: true)
    }

    func windowDidChangeScreen(_ notification: Notification) { epoch = UUID() }
    func windowDidChangeBackingProperties(_ notification: Notification) { epoch = UUID() }
    func windowWillClose(_ notification: Notification) { close() }

    func close() {
        guard !closed else { return }
        closed = true
        epoch = UUID()
        captureTask?.cancel()
        freshnessTask?.cancel()
        jumpTask?.cancel()
        freshnessTask = nil
        jumpTask = nil
        let elapsed = started.duration(to: .now)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "WindowPortal").info(
            "Portal closed: frames=\(self.state.captures), captureMilliseconds=\(self.state.captureMilliseconds), elapsed=\(String(describing: elapsed), privacy: .public)")
        state.image = nil
        state.close = nil
        state.jump = nil
        state.move = nil
        state.togglePause = nil
        panel.delegate = nil
        panel.handleKey = nil
        panel.close()
        panel.contentView = nil
        // Keep the coordinator slot until an uncancellable SDK request drains. Rapid close/pin cannot
        // accumulate more than four in-flight captures, even though the native panel closes immediately.
        if captureTask == nil { captureFinished() }
    }

    private func captureFinished() {
        captureTask = nil
        guard closed else { return }
        onClose?()
        onClose = nil
    }

    private func refresh() async {
        guard application?.isTerminated == false else {
            state.phase = .unavailable
            return
        }
        guard !suspended else { state.phase = .paused; return }
        guard CGPreflightScreenCaptureAccess() else {
            state.image = nil
            state.phase = .permissionRequired
            return
        }
        guard !state.userPaused, panel.occlusionState.contains(.visible) else {
            state.phase = .paused
            return
        }
        let expected = epoch
        let scale = panel.backingScaleFactor
        let bounds = panel.contentView?.bounds.size ?? CGSize(width: 360, height: 260)
        let pixels = CGSize(width: min(1280, bounds.width * scale), height: min(960, bounds.height * scale))
        let start = ContinuousClock.now
        let result = await capture.update(pixelSize: pixels)
        guard !closed, !Task.isCancelled, epoch == expected else { return }
        guard CGPreflightScreenCaptureAccess() else {
            state.image = nil
            state.phase = .permissionRequired
            return
        }
        switch result {
        case .frame(let image, let source):
            state.image = image
            state.source = source
            panel.title = state.sourceName
            state.phase = .live
            state.lastFrameAt = Date()
            lastSuccess = .now
            state.captures += 1
            let duration = start.duration(to: .now).components
            state.captureMilliseconds += Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        case .paused: state.phase = .paused
        case .unavailable: state.phase = .unavailable
        case .permissionRequired:
            state.image = nil
            state.phase = .permissionRequired
        case .stale: state.phase = state.image == nil ? .unavailable : .stale
        }
    }

    private func togglePause() {
        state.userPaused.toggle()
        epoch = UUID()
        state.phase = state.userPaused ? .paused : .connecting
    }

    private func move(x: CGFloat, y: CGFloat) {
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + x, y: panel.frame.minY + y))
        // Permit travel between adjacent displays, but never lose the title bar off the desktop.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 12)) }) {
            repairPlacement()
        }
    }

    private func jump() {
        guard jumpTask == nil, application?.isTerminated == false else { return }
        jumpTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let source = await capture.currentSource(), !closed, !Task.isCancelled else {
                if !closed, !Task.isCancelled {
                    state.jumpFailed = true
                    _ = application?.activate(options: [])
                }
                jumpTask = nil
                return
            }
            let service = AccessibilityApplicationWindowService()
            let session = UUID()
            var selected = false
            do {
                let summaries = try await service.discover(processes: [ApplicationProcessSnapshot(
                    processIdentifier: source.processIdentifier, isHidden: false, isActive: false)], sessionID: session)
                try Task.checkCancellation()
                let matches = summaries.filter { $0.title == source.title && $0.frame == source.frame }
                if matches.count == 1 {
                    try await service.selectWindow(matches[0].token)
                    selected = true
                }
            } catch { }
            await service.stop()
            guard !closed, !Task.isCancelled else { return }
            state.jumpFailed = !selected
            if !selected { _ = application?.activate(options: []) }
            jumpTask = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 40 : 10
        switch event.keyCode {
        case 123: move(x: -step, y: 0)
        case 124: move(x: step, y: 0)
        case 125: move(x: 0, y: -step)
        case 126: move(x: 0, y: step)
        case 36, 76: jump()
        case 49: togglePause()
        case 53: close()
        default: return false
        }
        return true
    }

    private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
