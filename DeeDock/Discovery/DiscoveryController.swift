import AppKit
import SwiftUI

/// Owns metadata observation and one nonactivating panel. Stop removes every timer and observer.
@MainActor
final class DiscoveryController {
    let engine = DiscoveryEngine()
    var interactionBlocked: () -> Bool = { true }
    var targetScreen: () -> NSScreen? = { nil }
    var openDestination: (DiscoveryProposal.Destination) -> Void = { _ in }
    private let watcher = ClipboardMuseumWatcher(pasteboard: .general)
    private var timer: Timer?
    private var panel: DiscoveryPanel?
    private var shownAt: Date?
    #if DEBUG
    private var isDebugPresentation = false

    /// Shows real callout chrome without consuming eligibility, cooldowns, or dismissals.
    /// Ordinary Settings windows may remain open; drag, sheets, and fullscreen still gate it.
    func debugShow(_ proposal: DiscoveryProposal) {
        guard engine.visible == nil, !suspended, menuDepth == 0, !interactionBlocked(),
              let screen = targetScreen() ?? NSScreen.main,
              !nativeBlocked(on: screen, allowOrdinaryWindows: true) else { return }
        closePanel()
        isDebugPresentation = true
        present(proposal, on: screen)
    }
    #endif
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var appObservers: [NSObjectProtocol] = []
    private var menuDepth = 0
    private var suspensionReasons: Set<String> = []
    private var suspended: Bool { !suspensionReasons.isEmpty }

    func start() {
        guard timer == nil else { return }
        watcher.changed = { [weak self] in self?.engine.record(.clipboardChanged, at: .now) }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "sleep"),
                               (NSWorkspace.screensDidSleepNotification, "screens"),
                               (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspensionReasons.insert(reason)
                    self?.watcher.stop(); self?.finish()
                }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "sleep"),
                               (NSWorkspace.screensDidWakeNotification, "screens"),
                               (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspensionReasons.remove(reason); self?.refresh() }
            })
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            })
        }
        let appCenter = NotificationCenter.default
        appObservers.append(appCenter.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuDepth += 1; self?.finish() }
        })
        appObservers.append(appCenter.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuDepth = max(0, self.menuDepth - 1)
            }
        })
        appObservers.append(appCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        })
        // Native idle/fullscreen state has no unified public notification, as in Atmosphere.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        engine.setEnabled(enabled)
        closePanel()
        refresh()
    }

    func markUsed(_ destination: DiscoveryProposal.Destination) {
        engine.markUsed(destination)
        if engine.visible == nil { closePanel() }
        refresh()
    }

    private func refresh() {
        #if DEBUG
        if isDebugPresentation {
            if suspended || menuDepth > 0 || interactionBlocked()
                || nativeBlocked(on: panel?.screen, allowOrdinaryWindows: true) {
                finish()
            }
            return
        }
        #endif
        guard !suspended, engine.enabled else { watcher.stop(); closePanel(); return }
        if engine.needsClipboardSignal { watcher.start() } else { watcher.stop() }
        guard engine.visible != nil || !engine.queue.isEmpty else { return }
        let now = Date.now
        let screen = targetScreen()
        let blocked = screen == nil || menuDepth > 0 || interactionBlocked() || nativeBlocked(on: screen)
        if let panel {
            if engine.visible == nil || blocked { finish(); return }
            // Leave the controls available while reading with the pointer or keyboard focus.
            if let shownAt, now.timeIntervalSince(shownAt) >= 20,
               !NSWorkspace.shared.isVoiceOverEnabled, !panel.isKeyWindow, !panel.frame.contains(NSEvent.mouseLocation) { finish() }
            return
        }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                          eventType: CGEventType(rawValue: UInt32.max)!)
        if let proposal = engine.advance(at: now, canPresent: !blocked && idle >= 2), let screen {
            present(proposal, on: screen)
        }
    }

    private func nativeBlocked(on screen: NSScreen?, allowOrdinaryWindows: Bool = false) -> Bool {
        guard let screen else { return true }
        let pointerInCallout = panel?.frame.contains(NSEvent.mouseLocation) == true
        if NSEvent.pressedMouseButtons != 0 && !pointerInCallout { return true }
        if NSApp.modalWindow != nil || NSApp.windows.contains(where: {
            $0 !== panel && $0.isVisible && ($0.attachedSheet != nil || (!allowOrdinaryWindows && $0.level == .normal))
        }) { return true }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return true }
        let quartz = AtmosphereDisplayLayout.quartzFrame(screen.frame,
                            primaryTop: NSScreen.screens.first?.frame.maxY ?? 0)
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return frame.insetBy(dx: -1, dy: -1).contains(quartz)
        }
    }

    private func present(_ proposal: DiscoveryProposal, on screen: NSScreen) {
        let panel = DiscoveryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenNone]
        panel.isExcludedFromWindowsMenu = true
        let view = NSHostingView(rootView: DiscoveryCalloutView(proposal: proposal,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            open: { [weak self] in
                guard let self else { return }
                markUsed(proposal.destination)
                openDestination(proposal.destination)
            }, snooze: { [weak self] in self?.finish() }, dismiss: { [weak self] in self?.finish(forever: true) }))
        let size = view.fittingSize
        // AppKit points, constrained to the chosen enabled display's usable frame.
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        panel.setFrame(CGRect(x: available.maxX - size.width, y: available.maxY - size.height,
                              width: size.width, height: size.height), display: false)
        panel.contentView = view
        self.panel = panel; shownAt = .now
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.finish() }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.finish(); return event
        }) { monitors.append(monitor) }
        panel.orderFrontRegardless()
    }

    private func finish(forever: Bool = false) {
        #if DEBUG
        if isDebugPresentation { closePanel(); return }
        #endif
        engine.finish(forever: forever, at: .now)
        closePanel()
    }

    private func closePanel() {
        #if DEBUG
        isDebugPresentation = false
        #endif
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        panel?.close(); panel = nil; shownAt = nil
    }

    func stop() {
        finish()
        watcher.stop(); watcher.changed = nil
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appObservers.removeAll(); menuDepth = 0
    }
}

/// Becomes key only through an explicit click, never on presentation or hover.
private final class DiscoveryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
