import AppKit
import ApplicationServices

/// Consumes the coordinator's existing pointer stream. No timer or window scan runs at idle.
@MainActor final class AppMeltProximityController {
    private weak var controller: AppMeltController?
    private let scanner = AppMeltProximityScanner()
    private let offer = AppMeltProximityOffer()
    private var source: AppMeltVisibleWindow?
    private var candidate: [AppMeltVisibleWindow] = []
    private var generation = UUID()
    private var held = false
    private var lastScan = Date.distantPast
    private var scan: Task<Void, Never>?
    private var dwell: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var connection: Task<Void, Never>?

    init(controller: AppMeltController) {
        self.controller = controller
        offer.connect = { [weak self] in self?.connect() }
        offer.dismiss = { [weak self] in self?.cancel() }
    }

    func observe(_ event: NSEvent, dockDragging: Bool) {
        if dockDragging { cancel(); return }
        if event.type == .keyDown, event.keyCode == 53 { cancel(); return }
        if event.type == .leftMouseDown {
            if offer.state.ready, offer.contains(NSEvent.mouseLocation) { return }
            cancel()
            guard event.window == nil, AXIsProcessTrusted(),
                  let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  controller?.pairs.contains(where: { $0.windows.contains { $0.processIdentifier == pid } }) != true else { return }
            held = true
            let stamp = generation
            let point = quartzPointer(event)
            scan = Task { [weak self] in
                guard let self else { return }
                let windows = await scanner.snapshot()
                guard generation == stamp, held, !Task.isCancelled else { return }
                // A title-area press plus an actual origin change distinguishes window drags
                // from text selection, scrolling, and dragging files inside app content.
                source = windows.first { $0.pid == pid && $0.frame.contains(point)
                    && point.y <= $0.frame.minY + 52 }
                scan = nil
            }
        } else if event.type == .leftMouseDragged {
            guard held, source != nil, scan == nil, Date().timeIntervalSince(lastScan) >= 0.12 else { return }
            lastScan = Date()
            let stamp = generation
            scan = Task { [weak self] in
                guard let self else { return }
                let windows = await scanner.snapshot()
                guard generation == stamp, held, !Task.isCancelled else { return }
                update(windows)
                scan = nil
            }
        } else if event.type == .leftMouseUp {
            guard connection == nil else { return }
            held = false
            scan?.cancel(); scan = nil
            guard offer.state.ready else { cancel(); return }
            offer.release()
            expiry?.cancel()
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.cancel()
            }
        } else if event.type == .rightMouseDown { cancel() }
    }

    /// `mouseLocation` is the global AppKit cursor. Quartz Y is measured down from the main
    /// display's top (`CGMainDisplayID`), including when the pointer is on another display.
    /// A nil-window global event has no local window to convert; local events use that window's screen point.
    private func quartzPointer(_ event: NSEvent) -> CGPoint {
        let appKit = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        return AppMeltGeometry.quartz(fromAppKit: appKit)
    }

    private func update(_ windows: [AppMeltVisibleWindow]) {
        guard let source, let moved = windows.first(where: { $0.id == source.id && $0.pid == source.pid }),
              abs(moved.frame.minX - source.frame.minX) + abs(moved.frame.minY - source.frame.minY) > 4,
              moved.frame.size == source.frame.size else { clearCandidate(); return }
        let paired = Set(controller?.pairs.flatMap { $0.windows.map(\.processIdentifier) } ?? [])
        // Quartz lists front to back. Do not offer a fully covered background window.
        let peers = windows.enumerated().filter { index, window in
            window.id != moved.id && !paired.contains(window.pid)
                && !windows.prefix(index).contains { front in
                    front.id != moved.id && front.frame.contains(window.frame)
                }
        }
        let target = peers.compactMap { _, peer -> (AppMeltVisibleWindow, CGFloat)? in
            AppMeltProximityGeometry.distance(moved.frame, peer.frame).map { (peer, $0) }
        }.min { $0.1 < $1.1 }?.0
        guard let target else { clearCandidate(); return }
        if candidate.count == 2, candidate[1].id == target.id,
           AppMeltGeometry.nearlyEqual(candidate[0].frame, moved.frame),
           AppMeltGeometry.nearlyEqual(candidate[1].frame, target.frame) { return }
        clearCandidate()
        candidate = [moved, target]
        let names = candidate.compactMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName }.joined(separator: " + ")
        offer.show(near: moved.frame.union(target.frame), names: names)
        let stamp = generation
        let expected = candidate
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, generation == stamp, held else { return }
            let latest = await scanner.snapshot()
            guard !Task.isCancelled, generation == stamp, held,
                  expected.allSatisfy({ old in latest.contains { $0.id == old.id && $0.pid == old.pid && AppMeltGeometry.nearlyEqual($0.frame, old.frame) } }) else {
                if !Task.isCancelled, generation == stamp { clearCandidate() }; return
            }
            offer.state.ready = true
        }
    }

    private func connect() {
        guard let controller, candidate.count == 2, !held, connection == nil else { return }
        expiry?.cancel()
        offer.state.busy = true
        let expected = candidate.sorted { $0.frame.minX < $1.frame.minX }
        let stamp = generation
        let session = UUID()
        connection = Task { [weak self] in
            guard let self else { return }
            var transferred = false
            do {
                let latest = await scanner.snapshot()
                guard expected.allSatisfy({ old in latest.contains { $0.id == old.id && $0.pid == old.pid && AppMeltGeometry.nearlyEqual($0.frame, old.frame) } }) else { throw WindowActionError.stale }
                let windows = try await controller.service.meltResolveVisible(expected, sessionID: session)
                try Task.checkCancellation()
                guard generation == stamp else { throw CancellationError() }
                let apps = expected.compactMap { NSRunningApplication(processIdentifier: $0.pid) }
                guard apps.count == 2 else { throw WindowActionError.stale }
                let pair = try await controller.create(sessionID: session, windows: windows,
                    names: apps.map { $0.localizedName ?? "" }, icons: apps.map { $0.icon ?? NSImage() })
                transferred = true
                offer.hide()
                if pair.message != nil { controller.showRecovery(pair) }
            } catch is CancellationError { }
            catch { if generation == stamp { offer.state.error = AppMeltFailure.message(for: error) } }
            if !transferred { await controller.service.discard(sessionID: session) }
            if generation == stamp { offer.state.busy = false; connection = nil }
        }
    }

    private func clearCandidate() {
        dwell?.cancel(); dwell = nil
        candidate = []; offer.hide()
    }

    func cancel() {
        generation = UUID(); held = false; source = nil
        scan?.cancel(); scan = nil; expiry?.cancel(); expiry = nil
        connection?.cancel(); connection = nil
        clearCandidate()
    }
}
