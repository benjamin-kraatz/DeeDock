import AppKit
import SwiftUI

/// Runs the enlarged preview for one Peek presentation: card dwell, the staged hero, and its capture.
///
/// This is a picture of the window, not the window. Nothing here raises, restores, or focuses a real
/// window; a click on the card still goes through Peek's ordinary selection, and `land(on:)` only
/// animates the picture onto the window that selection brings forward. The owning
/// `WindowPeekCoordinator` creates one per presentation and calls `stop()` when Peek closes.
///
/// Task ownership: at most one dwell, one leave-grace, one hi-res capture, and one click-settle task
/// exist at a time. Each is cancelled when superseded, and every result re-checks the exhibit it was
/// started for, so a late capture can never land on a different card. A landing deliberately outlives
/// Peek: `stop()` hands the stage panel to the landing, whose own deadline closes it.
@MainActor
final class WindowPeekEnlargeController {
    private let thumbnails: any WindowThumbnailServicing
    private weak var peek: WindowPeekPanelController?
    /// Collisions owned outside Peek (dock drags, App Fusion gestures) that must not be covered.
    private let externallyBlocked: () -> Bool
    private var stagePanel: WindowPeekStagePanelController?
    private var hovered: ApplicationWindowToken?
    /// A press or key dismisses the stage; the same card stays quiet until the pointer moves to another.
    private var suppressed: ApplicationWindowToken?
    private var staged: WindowPeekExhibit?
    private var dwellTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var clickTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var stopped = false
    /// Set once a click hands the stage panel to a landing, which then owns and closes it.
    private var landing: WindowPeekLanding?

    init(peek: WindowPeekPanelController, thumbnails: any WindowThumbnailServicing,
         externallyBlocked: @escaping () -> Bool) {
        self.peek = peek
        self.thumbnails = thumbnails
        self.externallyBlocked = externallyBlocked
        // Local only: clicks and keys in Peek's own panel. Outside clicks already close all of Peek.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            self?.observe(event)
            return event
        }
    }

    /// Pointer entered or left a card.
    func hover(_ token: ApplicationWindowToken, inside: Bool) {
        guard !stopped else { return }
        if inside {
            hovered = token
            leaveTask?.cancel()
            leaveTask = nil
            if suppressed == token { return }
            suppressed = nil
            dwellTask?.cancel()
            dwellTask = nil
            if staged?.token == token { return }
            let delay = WindowPeekEnlargeTiming.dwell(staged: staged != nil)
            dwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, hovered == token else { return }
                dwellTask = nil
                present(token)
            }
        } else {
            // Adjacent cards can report the new entry before the old exit.
            guard hovered == token else { return }
            hovered = nil
            dwellTask?.cancel()
            dwellTask = nil
            guard staged != nil else { return }
            leaveTask?.cancel()
            leaveTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: WindowPeekEnlargeTiming.leaveGrace)
                guard let self, !Task.isCancelled, hovered == nil else { return }
                leaveTask = nil
                dismiss()
            }
        }
    }

    /// Returns the stage to empty with a short fade, leaving Peek open.
    func dismiss() {
        dwellTask?.cancel()
        leaveTask?.cancel()
        captureTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        captureTask = nil
        if let staged { retire(staged) }
        staged = nil
        guard let stagePanel else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            stagePanel.stage.dimmed = false
            peek?.state.liftedID = nil
        }
    }

    /// Tears down tasks, the event monitor, and the panel. Idempotent. A landing in flight keeps the
    /// panel: Peek closes as soon as selection succeeds, which is exactly when the landing must continue.
    func stop() {
        guard !stopped else { return }
        stopped = true
        dwellTask?.cancel()
        leaveTask?.cancel()
        captureTask?.cancel()
        clickTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        captureTask = nil
        clickTask = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        staged = nil
        peek?.state.liftedID = nil
        if let landing {
            // The landing keeps itself and the panel alive until its fade ends.
            landing.peekDidClose()
            self.landing = nil
            stagePanel = nil
            return
        }
        stagePanel?.close(animated: true)
        stagePanel = nil
    }

    /// Selection of `token` is committing. If that card is staged, fly its image onto the real window
    /// so the preview appears to become it; otherwise, or without a usable frame, just dismiss.
    ///
    /// - Parameter windowFrame: the window's frame from discovery, in Quartz global coordinates
    ///   (top-left origin at the primary display). It may be slightly stale if the window moved since.
    func land(_ token: ApplicationWindowToken, windowFrame: CGRect?) {
        clickTask?.cancel()
        clickTask = nil
        guard !stopped, landing == nil, let exhibit = staged, exhibit.token == token, !exhibit.reduceMotion,
              let windowFrame, let stagePanel, let primary = NSScreen.screens.first else {
            dismiss()
            return
        }
        let target = WindowPeekEnlargeGeometry.appKit(fromQuartz: windowFrame, primaryMaxY: primary.frame.maxY)
        // The stage covers one display; a window elsewhere would fly out of view and be clipped.
        guard target.intersection(stagePanel.screenFrame).width * target.intersection(stagePanel.screenFrame).height
                >= target.width * target.height * 0.5 else {
            dismiss()
            return
        }
        dwellTask?.cancel()
        leaveTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        // A hi-res capture already on its way is still welcome; it only sharpens the flight.
        staged = nil
        let landing = WindowPeekLanding(panel: stagePanel, exhibit: exhibit)
        self.landing = landing
        landing.start(target: stagePanel.local(target))
    }

    private func observe(_ event: NSEvent) {
        guard !stopped, landing == nil else { return }
        switch event.type {
        case .leftMouseDown:
            // The card's click commits on mouse-up through `land(_:windowFrame:)`, so a press alone
            // keeps the stage; the same card stays quiet afterwards.
            suppressed = hovered
        case .leftMouseUp:
            // A release that selected nothing (a button, empty panel space) still clears the stage.
            // Selection runs synchronously inside this event's dispatch, before this task resumes.
            guard staged != nil else { return }
            clickTask?.cancel()
            clickTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled, landing == nil else { return }
                clickTask = nil
                dismiss()
            }
        default:
            suppressed = hovered
            dismiss()
        }
    }

    private var blocked: Bool {
        guard let state = peek?.state else { return true }
        return state.routingFiles || state.portalDragging || state.actionBusy || state.actionMenuTracking
            || state.phase != .windows || QuarantineStampController.shared.armed || externallyBlocked()
    }

    private func present(_ token: ApplicationWindowToken) {
        guard !stopped, !blocked, let peek, let screen = peek.screen,
              let card = peek.state.cards.first(where: { $0.id == token }),
              let preview = card.thumbnail else { return }
        let imageSize = CGSize(width: CGFloat(preview.width) / max(1, screen.backingScaleFactor),
                               height: CGFloat(preview.height) / max(1, screen.backingScaleFactor))
        guard let hero = WindowPeekEnlargeGeometry.hero(windowSize: card.window.frame?.size ?? imageSize,
                                                        screenFrame: screen.frame,
                                                        visibleFrame: peek.visibleFrame,
                                                        peekFrame: peek.frame, edge: peek.edge) else { return }
        let stagePanel = stagePanel(for: screen.frame)
        let source = peek.state.artworkFrames[token].map { frame in
            // The card draws its thumbnail scaled to fit, so fly from the pixels, not the slot.
            stagePanel.local(WindowPeekEnlargeGeometry.aspectFit(
                CGSize(width: preview.width, height: preview.height), in: peek.screenRect(fromContent: frame)))
        }
        let reusable = staged?.token == token ? staged?.detail : nil
        if let staged { retire(staged) }
        captureTask?.cancel()
        captureTask = nil

        let exhibit = WindowPeekExhibit(
            token: token,
            title: ApplicationContextMenuProjection.windowTitle(
                card.window, untitled: String(localized: .applicationMenuUntitledWindow)),
            preview: preview, detail: reusable, source: source, hero: stagePanel.local(hero),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        staged = exhibit
        stagePanel.stage.cutout = stagePanel.local(peek.frame)
        stagePanel.stage.exhibits.append(exhibit)
        stagePanel.show()
        withAnimation(exhibit.liftAnimation) {
            stagePanel.stage.dimmed = true
            peek.state.liftedID = token
        }
        if reusable == nil {
            requestDetail(for: card.window, exhibit: exhibit,
                          pixels: WindowPeekEnlargeGeometry.capturePixels(hero: hero.size,
                                                                         backingScale: screen.backingScaleFactor))
        }
    }

    /// The strip thumbnail is at most twice a card's size, which is soft at hero size on Retina.
    private func requestDetail(for window: ApplicationWindowSummary, exhibit: WindowPeekExhibit, pixels: CGSize) {
        guard !window.isMinimized else { return }
        captureTask = Task { @MainActor [weak self, thumbnails] in
            let image = await thumbnails.capture(window, fittingPixels: pixels)
            guard let self, !Task.isCancelled, staged === exhibit else { return }
            captureTask = nil
            guard let image else { return }
            // The exhibit view crossfades from the strip image when this arrives.
            exhibit.detail = image
        }
    }

    private func retire(_ exhibit: WindowPeekExhibit) {
        guard let stagePanel else { return }
        withAnimation(.easeIn(duration: 0.16)) {
            exhibit.leaving = true
        } completion: { [weak stagePanel] in
            guard let stagePanel else { return }
            stagePanel.stage.exhibits.removeAll { $0 === exhibit }
            stagePanel.hideIfIdle()
        }
    }

    /// Reuses the panel while Peek stays on one display, replacing it if the display changed.
    private func stagePanel(for screenFrame: CGRect) -> WindowPeekStagePanelController {
        if let stagePanel, stagePanel.screenFrame == screenFrame { return stagePanel }
        stagePanel?.close(animated: false)
        staged = nil
        let next = WindowPeekStagePanelController(screenFrame: screenFrame)
        stagePanel = next
        return next
    }
}
