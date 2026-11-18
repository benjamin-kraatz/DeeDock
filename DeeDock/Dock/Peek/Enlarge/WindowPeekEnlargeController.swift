import AppKit
import SwiftUI

/// Runs the enlarged preview for one Peek presentation: card dwell, the staged hero, and its capture.
///
/// This is a picture of the window, not the window. Nothing here raises, restores, or focuses a real
/// window; a click on the card still goes through Peek's ordinary selection, and `land(on:)` only
/// animates the picture onto the window that selection brings forward. The owning
/// `WindowPeekCoordinator` creates one per presentation and calls `stop()` when Peek closes.
///
/// Task ownership: at most one dwell, one leave-grace, one corridor-grace, one hi-res capture, and
/// one click-settle task exist at a time. Each is cancelled when superseded, and every result
/// re-checks the exhibit it was started for, so a late capture can never land on a different card. A
/// landing deliberately outlives Peek: `stop()` hands the stage panel to the landing, whose own
/// deadline closes it. Stow flights after Save are animations, not tasks; `stowsInFlight` counts
/// them until their completions run.
///
/// Holding: the pointer may leave the cards for the picture. `pointerMoved(_:)` decides, through
/// `WindowPeekEnlargeHold`, whether the stage is held (pointer on the hero, toolbar shown), waiting
/// (pointer in the corridor between Peek and the hero), or dismissed. `retainsPeek` lets the owning
/// coordinator keep Peek open in the first two states.
@MainActor
final class WindowPeekEnlargeController {
    private let thumbnails: any WindowThumbnailServicing
    private let classifier: any WindowPreviewClassifying
    private weak var peek: WindowPeekPanelController?
    /// Opens the markup editor for the staged card; set by the coordinator.
    var markup: ((ApplicationWindowToken) -> Void)?
    /// The hold state changed; the coordinator re-evaluates whether Peek stays open.
    var heldChanged: (() -> Void)?
    /// Where the toolbar's Save puts the picture; set by the coordinator before the first hold.
    var saveTarget: WindowPeekHeroSaveTarget = .shelf
    /// Writes the staged picture (image, window title) to `saveTarget`; set by the coordinator.
    /// Returns `nil` when nothing was saved, after the coordinator has reported why.
    var savePicture: ((CGImage, String) -> WindowPeekSavedPicture?)?
    /// Saved pictures still flying into their tile. Peek stays open meanwhile, so the dock keeps
    /// the tile on screen until the picture lands.
    private var stowsInFlight = 0
    private var heroToolbar: WindowPeekHeroToolbarPanel?
    private var heroPrivacy: WindowPeekHeroPrivacyPanel?
    private var held = false
    private var corridorTask: Task<Void, Never>?
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
         classifier: any WindowPreviewClassifying, externallyBlocked: @escaping () -> Bool) {
        self.peek = peek
        self.thumbnails = thumbnails
        self.classifier = classifier
        self.externallyBlocked = externallyBlocked
        // Local only: clicks and keys in Peek's own panel. Outside clicks already close all of Peek.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            self?.observe(event)
            return event
        }
        peek.ownsAuxiliaryWindow = { [weak self] window in self?.ownsHeroControl(window) == true }
        peek.enlargedPreviewControl = { [weak self] in
            guard let self, heroPrivacy != nil else { return nil }
            return staged?.sensitive?.control()
        }
    }

    /// Whether the pointer is on or heading for the staged picture, which keeps Peek open.
    var retainsPeek: Bool {
        stowsInFlight > 0 || (staged != nil && landing == nil && (held || corridorTask != nil))
    }

    /// The staged card's picture and where it is on screen, for a hand-off to the markup editor.
    func stagedExhibit(for token: ApplicationWindowToken) -> (frame: CGRect, image: CGImage)? {
        guard let staged, staged.token == token, let stagePanel, let image = staged.clearedImage else { return nil }
        return (WindowPeekEnlargeGeometry.screen(staged.hero, in: stagePanel.screenFrame), image)
    }

    /// The hero block in screen coordinates: the image plus the placard below it.
    private var heroBlock: CGRect? {
        guard let staged, let stagePanel else { return nil }
        let hero = WindowPeekEnlargeGeometry.screen(staged.hero, in: stagePanel.screenFrame)
        return CGRect(x: hero.minX, y: hero.minY - WindowPeekEnlargeGeometry.placardSpace,
                      width: hero.width, height: hero.height + WindowPeekEnlargeGeometry.placardSpace)
    }

    /// Pointer moved anywhere on screen. Called by the coordinator before it decides on closing.
    func pointerMoved(_ point: CGPoint) {
        guard !stopped, landing == nil, staged != nil, let heroBlock, let peek else { return }
        switch WindowPeekEnlargeHold.retention(pointer: point, hero: heroBlock, peek: peek.frame) {
        case .hero:
            corridorTask?.cancel()
            corridorTask = nil
            leaveTask?.cancel()
            leaveTask = nil
            if !held { hold() }
        case .corridor:
            if held { release(); startCorridorGrace() }
            else if hovered == nil, leaveTask == nil, corridorTask == nil { startCorridorGrace() }
        case .none:
            if held { release() }
            corridorTask?.cancel()
            corridorTask = nil
            if hovered == nil { dismiss() }
        }
    }

    private func hold() {
        guard let staged, let stagePanel else { return }
        held = true
        guard staged.clearedImage != nil else { heldChanged?(); return }
        let hero = WindowPeekEnlargeGeometry.screen(staged.hero, in: stagePanel.screenFrame)
        if heroToolbar == nil {
            // One toolbar serves every card staged during this Peek, so it reads the current exhibit.
            heroToolbar = WindowPeekHeroToolbarPanel(level: NSWindow.Level(rawValue: stagePanel.level.rawValue + 1), actions: .init(
                markup: { [weak self] in
                    guard let self, let current = self.staged, current.clearedImage != nil else { return }
                    markup?(current.token)
                },
                copy: { [weak self] in self?.copyStaged() ?? false },
                saveTarget: saveTarget,
                save: { [weak self] in self?.saveStaged() ?? .failed }))
        }
        heroToolbar?.show(forHero: hero)
        heldChanged?()
    }

    private func release() {
        held = false
        heroToolbar?.hide()
        heldChanged?()
    }

    /// The pointer is between Peek and the picture; give it a moment to arrive, then let go.
    private func startCorridorGrace() {
        corridorTask?.cancel()
        corridorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: WindowPeekEnlargeHold.corridorGrace)
            guard let self, !Task.isCancelled else { return }
            corridorTask = nil
            guard !held, hovered == nil else { return }
            dismiss()
            heldChanged?()
        }
    }

    private func copyStaged() -> Bool {
        guard let image = staged?.clearedImage else { return false }
        return WindowMarkupExport.copy(image)
    }

    /// Saves the staged picture to the Shelf (or Downloads) without a panel, then flies it into that
    /// tile so the user sees where it went. The picture is at most hero-sized; the markup editor is
    /// the way to a full-resolution file.
    ///
    /// A save panel would open behind the stage and the hero, which sit above every ordinary window,
    /// so this writes directly. Without a tile to aim at, or with Reduce Motion, the stage stays and
    /// the toolbar confirms in place.
    private func saveStaged() -> WindowPeekHeroSaveOutcome {
        guard let staged, let image = staged.clearedImage, let savePicture,
              let saved = savePicture(image, staged.title) else { return .failed }
        guard let tile = saved.tile, !staged.reduceMotion, let stagePanel, let peek,
              stagePanel.screenFrame.intersects(tile) else {
            saved.arrived()
            return .saved
        }
        stow(staged, into: stagePanel.local(tile), edge: peek.edge, on: stagePanel, arrived: saved.arrived)
        return .flew
    }

    /// Hands the staged exhibit to a stow flight and returns the stage to empty.
    ///
    /// The exhibit leaves `staged` at once, so pointer tracking, a new hover, or a dismissal no longer
    /// touch it; the completion removes it from whichever stage it is still on. The dim lifts while it
    /// flies, and Peek stays retained until it lands.
    private func stow(_ exhibit: WindowPeekExhibit, into tile: CGRect, edge: DockEdge,
                      on stagePanel: WindowPeekStagePanelController, arrived: @escaping () -> Void) {
        corridorTask?.cancel()
        corridorTask = nil
        leaveTask?.cancel()
        leaveTask = nil
        captureTask?.cancel()
        captureTask = nil
        held = false
        heroToolbar?.hide()
        staged = nil
        stowsInFlight += 1
        exhibit.stow = WindowPeekStowPath(hero: exhibit.hero, tile: tile, edge: edge)
        withAnimation(.easeOut(duration: 0.3)) {
            stagePanel.stage.dimmed = false
            peek?.state.liftedID = nil
        }
        withAnimation(WindowPeekStowPath.animation) {
            exhibit.stowProgress = 1
        } completion: { [weak self, weak stagePanel] in
            stagePanel?.stage.exhibits.removeAll { $0 === exhibit }
            stagePanel?.hideIfIdle()
            arrived()
            guard let self else { return }
            stowsInFlight -= 1
            heldChanged?()
        }
    }

    /// The dwell may finish before the off-main classifier. Pick up the result if the pointer stayed.
    func thumbnailReady(for token: ApplicationWindowToken) {
        guard hovered == token, suppressed != token, dwellTask == nil, staged?.token != token else { return }
        present(token)
    }

    /// Pointer entered or left a card.
    func hover(_ token: ApplicationWindowToken, inside: Bool) {
        guard !stopped else { return }
        if inside {
            if let staged, staged.token != token {
                closeHeroPrivacy()
                captureTask?.cancel()
                captureTask = nil
            }
            hovered = token
            leaveTask?.cancel()
            leaveTask = nil
            if suppressed == token { return }
            suppressed = nil
            dwellTask?.cancel()
            dwellTask = nil
            if let staged, staged.token == token {
                if heroPrivacy == nil, let stagePanel { showHeroPrivacy(for: staged, on: stagePanel) }
                return
            }
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
                // The pointer may be on its way to the picture rather than away from it.
                if let heroBlock, let peek {
                    switch WindowPeekEnlargeHold.retention(pointer: NSEvent.mouseLocation, hero: heroBlock, peek: peek.frame) {
                    case .hero: hold(); return
                    case .corridor: startCorridorGrace(); return
                    case .none: break
                    }
                }
                dismiss()
            }
        }
    }

    /// Returns the stage to empty with a short fade, leaving Peek open.
    func dismiss() {
        dwellTask?.cancel()
        leaveTask?.cancel()
        captureTask?.cancel()
        corridorTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        captureTask = nil
        corridorTask = nil
        let wasHeld = held
        held = false
        heroToolbar?.hide()
        closeHeroPrivacy()
        if let staged { retire(staged) }
        staged = nil
        // Notified after the stage is empty, so the coordinator's re-evaluation cannot re-hold it.
        if wasHeld { heldChanged?() }
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
        corridorTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        captureTask = nil
        clickTask = nil
        corridorTask = nil
        held = false
        heroToolbar?.close()
        heroToolbar = nil
        closeHeroPrivacy()
        markup = nil
        savePicture = nil
        heldChanged = nil
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
              exhibit.clearedImage != nil, let windowFrame, let stagePanel, let primary = NSScreen.screens.first else {
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
        // The hero controls act on the stage. A privacy shortcut leaves its exhibit in place.
        if ownsHeroControl(event.window) { return }
        if heroPrivacy != nil, event.type == .keyDown, WindowPreviewRevealShortcut.matches(event) { return }
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
        return state.routingFiles || state.actionBusy || state.actionMenuTracking
            || state.phase != .windows || externallyBlocked()
    }

    private func present(_ token: ApplicationWindowToken) {
        guard !stopped, !blocked, let peek, let screen = peek.screen,
              let card = peek.state.cards.first(where: { $0.id == token }) else { return }
        let preview = card.thumbnail
        let sensitive = sensitiveExhibit(for: card, state: peek.state)
        guard preview != nil || sensitive != nil else { return }
        Analytics.count(.peekEnlarge)
        let backingScale = max(1, screen.backingScaleFactor)
        let imageSize = preview.map {
            CGSize(width: CGFloat($0.width) / backingScale, height: CGFloat($0.height) / backingScale)
        }
        guard let windowSize = card.window.frame?.size ?? imageSize,
              let hero = WindowPeekEnlargeGeometry.hero(windowSize: windowSize,
                                                        screenFrame: screen.frame,
                                                        visibleFrame: peek.visibleFrame,
                                                        peekFrame: peek.frame, edge: peek.edge) else { return }
        let stagePanel = stagePanel(for: screen.frame)
        let source = peek.state.artworkFrames[token].map { frame in
            let artwork = peek.screenRect(fromContent: frame)
            // Cleared artwork fits its pixels into the card. A cover fills the card's artwork slot.
            let source = imageSize.map { WindowPeekEnlargeGeometry.aspectFit($0, in: artwork) } ?? artwork
            return stagePanel.local(source)
        }
        let reusable = staged?.token == token ? staged?.detail : nil
        if held { release() }
        closeHeroPrivacy()
        if let staged { retire(staged) }
        captureTask?.cancel()
        captureTask = nil

        let exhibit = WindowPeekExhibit(
            token: token,
            title: ApplicationContextMenuProjection.windowTitle(
                card.window, untitled: String(localized: .applicationMenuUntitledWindow)),
            preview: preview, detail: reusable, source: source, hero: stagePanel.local(hero),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        exhibit.sensitive = sensitive
        staged = exhibit
        stagePanel.stage.cutout = stagePanel.local(peek.frame)
        stagePanel.stage.exhibits.append(exhibit)
        stagePanel.show()
        withAnimation(exhibit.liftAnimation) {
            stagePanel.stage.dimmed = true
            peek.state.liftedID = token
        }
        if sensitive != nil {
            showHeroPrivacy(for: exhibit, on: stagePanel)
        } else if reusable == nil {
            requestDetail(for: card, exhibit: exhibit,
                          pixels: WindowPeekEnlargeGeometry.capturePixels(hero: hero.size,
                                                                         backingScale: screen.backingScaleFactor))
        }
    }

    /// The strip image is only as sharp as the card. `pixels` is already the hero in backing pixels
    /// and must reach `fittingPixels` unchanged.
    private func requestDetail(for card: WindowPeekCard, exhibit: WindowPeekExhibit, pixels: CGSize) {
        let window = card.window
        guard !window.isMinimized else { return }
        captureTask = Task { @MainActor [weak self, thumbnails, classifier] in
            let image = await thumbnails.capture(window, fittingPixels: pixels)
            guard let self, !Task.isCancelled, staged === exhibit else { return }
            guard let image else { captureTask = nil; return }
            let preview = await ClassifiedWindowPreview.classify(image, using: classifier)
            guard !Task.isCancelled, staged === exhibit, let state = peek?.state,
                  state.cards.contains(where: { $0.captureRevision == card.captureRevision }) else { return }
            captureTask = nil
            if let image = preview.clearedImage {
                // The stage crossfades only between independently cleared frames.
                exhibit.detail = image
            } else if let refreshed = state.applyPreview(preview, to: card),
                      let sensitive = sensitiveExhibit(for: refreshed, state: state), let stagePanel {
                // A sharper capture can change the privacy decision. Remove cleared artwork and
                // export controls before replacing it with the cover for this newly classified frame.
                heroToolbar?.close()
                heroToolbar = nil
                exhibit.detail = nil
                exhibit.preview = nil
                exhibit.sensitive = sensitive
                showHeroPrivacy(for: exhibit, on: stagePanel)
            } else {
                dismiss()
            }
        }
    }

    private func sensitiveExhibit(for card: WindowPeekCard, state: WindowPeekState) -> WindowPeekSensitiveExhibit? {
        guard let preview = card.preview, preview.decision == .sensitive else { return nil }
        let token = card.id, frame = preview.id
        return .init(image: { [weak state] in
            guard let state, let current = state.cards.first(where: { $0.id == token && $0.preview?.id == frame })
            else { return nil }
            return state.revealedImage(for: current)
        }, control: { [weak state] in
            guard let state, let current = state.cards.first(where: { $0.id == token && $0.preview?.id == frame })
            else { return nil }
            return state.previewControl(for: current)
        })
    }

    private func showHeroPrivacy(for exhibit: WindowPeekExhibit, on stagePanel: WindowPeekStagePanelController) {
        guard let sensitive = exhibit.sensitive else { return }
        closeHeroPrivacy()
        heroPrivacy = WindowPeekHeroPrivacyPanel(
            hero: WindowPeekEnlargeGeometry.screen(exhibit.hero, in: stagePanel.screenFrame),
            level: NSWindow.Level(rawValue: stagePanel.level.rawValue + 1), sensitive: sensitive)
    }

    private func closeHeroPrivacy() {
        heroPrivacy?.close()
        heroPrivacy = nil
    }

    private func ownsHeroControl(_ window: NSWindow?) -> Bool {
        heroToolbar?.owns(window) == true || heroPrivacy?.owns(window) == true
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
        closeHeroPrivacy()
        stagePanel?.close(animated: false)
        staged = nil
        let next = WindowPeekStagePanelController(screenFrame: screenFrame)
        stagePanel = next
        return next
    }
}
