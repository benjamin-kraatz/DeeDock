import AppKit
import SwiftUI

/// Drop to Place: drag an app tile far enough out of the dock and release it to open the app,
/// or move its front window, with the window's top-left corner at the drop point.
///
/// `DockDragCoordinator` owns the native drag and decides the zone (see ``DockDragZone``); this
/// controller owns everything after that decision: the ghost and outlines, the landing pad,
/// the placement itself, window memory, the Unpin Undo toast, and analytics.
///
/// The pointer path (``update(zone:pointer:shift:)``) is pure geometry plus model writes. The
/// only Accessibility read during a drag is one front-window read when a running app's drag
/// starts, which runs off the main actor and lands whenever it is ready.
@MainActor
final class DropToPlaceController {
    /// The connected displays with their persistent identities. Set by the coordinator.
    var displays: () -> [DisplaySnapshot] = { [] }

    private let overlay = DropPlacementOverlayController()
    private var model: DropPlacementOverlayModel { overlay.model }
    private let memory: DropPlacementWindowMemory
    private let accessibility: DropPlacementAccessibility
    private let service: DropPlacementService
    private lazy var recorder = DropPlacementWindowRecorder(memory: memory, accessibility: accessibility) { [weak self] in
        self?.displays() ?? []
    }
    private let undoToast = DockUnpinUndoController()
    private var session: Session?
    /// Waits one frame after arming so the ghost renders at icon size before it springs open.
    private var armTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// Per-drag state. Screens and dock reservations are captured once, at drag start.
    private struct Session {
        let token = UUID()
        let reference: ApplicationReference
        let name: String
        let tint: Color
        let running: Bool
        let trusted: Bool
        let reduceMotion: Bool
        /// Each display's frame and usable frame, AppKit global coordinates.
        let screens: [(frame: CGRect, usable: CGRect)]
        /// The remembered frame on a connected display, with that display's usable frame.
        /// Nil for running apps: the magnet only brings back closed apps.
        let memory: (frame: CGRect, usable: CGRect)?
        /// The remembered size, the base size's fallback while a running window is unread.
        let rememberedSize: CGSize?
        var runningFrame: CGRect?
        var armed = false
        var drawAnchor: CGPoint?
        var springUntil = ContinuousClock.now
        var kind: DropPlacementKind?
        var target: DropPlacementTarget?
    }

    init(defaults: UserDefaults? = .standard) {
        let memory = DropPlacementWindowMemory(defaults: defaults)
        let accessibility = DropPlacementAccessibility()
        self.memory = memory
        self.accessibility = accessibility
        service = DropPlacementService(accessibility: accessibility)
    }

    func start() { recorder.start() }

    func stop() {
        recorder.stop()
        service.stop()
        undoToast.stop()
        armTask?.cancel(); armTask = nil
        hideTask?.cancel(); hideTask = nil
        session = nil
        overlay.stop()
    }

    /// Whether Drop to Place applies to `item`: an available app other than DOKK itself.
    static func canPlace(_ item: DockItem) -> Bool {
        item.isAvailable && !AppDockPresence.representsCurrentApplication(item.reference)
    }

    // MARK: Drag

    /// Prepares a drag of `item`. Shows the remembered or current frame outline at once.
    /// - Parameter reservedDocks: Resting glass of every dock that keeps its space (not auto-hiding).
    func beginDrag(_ item: DockItem, reservedDocks: [CGRect]) {
        endDrag()
        // Dragging the same app again replaces a placement that is still waiting.
        service.cancel(applicationID: item.id)
        fadePads(for: item.id)
        let workspace = NSWorkspace.shared
        let screens = NSScreen.screens.map {
            (frame: $0.frame, usable: DropPlacementGeometry.usableFrame(visible: $0.visibleFrame, docks: reservedDocks))
        }
        let entry = item.reference.bundleIdentifier.flatMap(memory.entry(for:))
        let remembered: (frame: CGRect, usable: CGRect)? = entry.flatMap { entry in
            displays().first { $0.id == entry.displayID }.map {
                (entry.frame, DropPlacementGeometry.usableFrame(visible: $0.visibleFrame, docks: reservedDocks))
            }
        }
        let session = Session(
            reference: item.reference, name: item.reference.name,
            tint: DockIconAccent.accent(for: item.icon, identity: item.id) ?? Color(red: 0.44, green: 0.69, blue: 1),
            running: item.isRunning, trusted: AXIsProcessTrusted(),
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            screens: screens, memory: item.isRunning ? nil : remembered, rememberedSize: entry?.frame.size)
        self.session = session
        model.reduceMotion = session.reduceMotion
        model.reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        overlay.prepare()
        if let remembered = session.memory, let entry {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            let when = formatter.localizedString(for: entry.date, relativeTo: Date())
            showOutline(.init(frame: DropPlacementGeometry.clamp(remembered.frame, into: remembered.usable),
                              label: String(localized: .dropPlaceLastHere(when: when)), hot: false))
        }
        if item.isRunning, session.trusted, let app = DropPlacementService.runningApplication(for: item.reference) {
            let token = session.token, pid = app.processIdentifier
            Task { [weak self, accessibility] in
                guard let quartz = await accessibility.frontWindowFrame(processIdentifier: pid),
                      let self, self.session?.token == token else { return }
                let frame = DropPlacementService.appKit(quartz)
                self.session?.runningFrame = frame
                showOutline(.init(frame: frame, label: String(localized: .dropPlaceNowHere), hot: false))
            }
        }
    }

    /// Follows the pointer. Cheap enough for every drag event: geometry and model writes only.
    func update(zone: DockDragZone, pointer: CGPoint, shift: Bool) {
        guard var session else { return }
        guard zone == .place else {
            if session.armed { disarm() }
            return
        }
        let target = resolve(&session, pointer: pointer, shift: shift)
        let now = ContinuousClock.now
        if !session.armed {
            session.armed = true
            session.kind = target.kind
            session.springUntil = now + .milliseconds(420)
            self.session = session
            arm(at: pointer, target: target)
        } else {
            if target.kind != session.kind {
                session.kind = target.kind
                session.springUntil = max(session.springUntil, now + .milliseconds(360))
            }
            self.session = session
            apply(target, springPosition: now < session.springUntil || target.kind != .free)
        }
        if model.outline != nil, model.outline?.hot != (target.kind == .memory) {
            withAnimation(session.reduceMotion ? nil : .easeOut(duration: 0.2)) { model.outline?.hot = target.kind == .memory }
        }
    }

    /// Ends a drag that did not place: cancel, fly back, unpin, or a drop on a dock.
    func endDrag() {
        armTask?.cancel(); armTask = nil
        guard session != nil else { return }
        session = nil
        withAnimation(.easeOut(duration: 0.18)) {
            model.ghost = nil
            model.outline = nil
        }
        syncPanels()
    }

    /// Releases the drag in the Place zone at `pointer`.
    /// - Parameter open: Opens or activates the app through the dock (bounce, errors) and
    ///   reports success. Without Accessibility this is all that happens.
    func commit(at pointer: CGPoint, shift: Bool, open: @escaping (@escaping (Bool) -> Void) -> Void) {
        guard var session else { return }
        let target = resolve(&session, pointer: pointer, shift: shift)
        let reference = session.reference, running = session.running
        guard session.trusted else {
            endDrag()
            open { _ in }
            Analytics.track(.dockAppPlaced(outcome: .openedUnplaced, kind: target.kind, running: running))
            return
        }
        armTask?.cancel(); armTask = nil
        self.session = nil
        withAnimation(.easeOut(duration: 0.18)) { model.outline = nil }
        let padTitle: LocalizedStringResource = running ? .dropPlaceMoving(appName: session.name)
            : .dropPlaceOpening(appName: session.name)
        let pad = DropPlacementOverlayModel.Pad(id: UUID(), applicationID: reference.id, frame: target.frame,
                                                title: String(localized: padTitle), tint: session.tint)
        hideTask?.cancel(); hideTask = nil
        // The pad replaces the ghost in place, without a transition, so release reads as one surface.
        withTransaction(Transaction(animation: nil)) {
            model.ghost = nil
            model.pads.append(pad)
        }
        overlay.refresh()
        service.place(.init(reference: reference, frame: target.frame, open: open)) { [weak self] outcome, accepted in
            guard let self else { return }
            finishPad(pad.id, handoff: outcome == .placed || outcome == .moved)
            Analytics.track(.dockAppPlaced(outcome: outcome, kind: target.kind, running: running))
            if let accepted, let bundleIdentifier = reference.bundleIdentifier {
                recorder.remember(accepted, for: bundleIdentifier)
            }
        }
    }

    // MARK: Unpin Undo

    /// Offers Undo for a drag-out unpin.
    func offerUndo(appName: String, glass: CGRect, edge: DockEdge, undo: @escaping () -> Void) {
        undoToast.show(appName: appName, glass: glass, edge: edge) {
            Analytics.count(.pinUnpinUndone)
            undo()
        }
    }

    // MARK: Presentation

    private func resolve(_ session: inout Session, pointer: CGPoint, shift: Bool) -> DropPlacementTarget {
        let usable = session.screens.first { Self.contains($0.frame, pointer) }?.usable
            ?? session.screens.first?.usable ?? CGRect(origin: pointer, size: DropPlacementGeometry.defaultSize)
        if shift {
            if session.drawAnchor == nil { session.drawAnchor = DropPlacementGeometry.drawAnchor(pointer: pointer, usable: usable) }
        } else {
            session.drawAnchor = nil
        }
        let base = DropPlacementGeometry.baseSize(running: session.runningFrame?.size, remembered: session.rememberedSize,
                                                  usable: usable)
        let target = DropPlacementGeometry.target(.init(pointer: pointer, usable: usable, baseSize: base,
                                                         memory: session.memory, drawAnchor: session.drawAnchor))
        session.target = target
        return target
    }

    /// The pointer can sit exactly on a display's top or right edge, which `CGRect.contains` excludes.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Fades the ghost in at icon size on the pointer, then springs it to `target` a frame later.
    private func arm(at pointer: CGPoint, target: DropPlacementTarget) {
        guard let session else { return }
        hideTask?.cancel(); hideTask = nil
        let start = session.reduceMotion ? target.frame : DropPlacementGeometry.iconFrame(at: pointer)
        withAnimation(.easeOut(duration: 0.18)) { model.ghost = ghost(for: target, frame: start) }
        overlay.refresh()
        guard !session.reduceMotion else { return }
        armTask?.cancel()
        let token = session.token
        armTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, let self, let session = self.session, session.token == token, session.armed,
                  let target = session.target else { return }
            apply(target, springPosition: true)
        }
    }

    private func disarm() {
        armTask?.cancel(); armTask = nil
        session?.armed = false
        session?.drawAnchor = nil
        session?.kind = nil
        withAnimation(.easeOut(duration: 0.18)) {
            model.ghost = nil
            model.outline?.hot = false
        }
        syncPanels()
    }

    /// Writes the ghost. Position springs only while arming, after a kind change, and for
    /// snapped kinds; free movement sets it without animation so it tracks the pointer exactly.
    /// Size changes spring in the view itself.
    private func apply(_ target: DropPlacementTarget, springPosition: Bool) {
        guard let session else { return }
        let ghost = ghost(for: target, frame: target.frame)
        guard model.ghost != ghost else { return }
        if springPosition, !session.reduceMotion {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) { model.ghost = ghost }
        } else {
            model.ghost = ghost
        }
    }

    private func ghost(for target: DropPlacementTarget, frame: CGRect) -> DropPlacementOverlayModel.Ghost {
        guard let session else { return .init(frame: frame, title: "", subtitle: "", tint: .clear) }
        let name = session.name
        let width = Int(target.frame.width.rounded()), height = Int(target.frame.height.rounded())
        let title: String, subtitle: String
        if !session.trusted {
            title = String(localized: .dropPlaceOpenNormally)
            subtitle = String(localized: .dropPlaceAccessibilityNeeded)
        } else {
            switch target.kind {
            case .free:
                let verb: LocalizedStringResource = session.running ? .dropPlaceMoveHere : .dropPlaceOpenHere
                let size: LocalizedStringResource = target.nudged
                    ? .dropPlaceSubtitleSizeNudged(appName: name, width: width, height: height)
                    : .dropPlaceSubtitleSize(appName: name, width: width, height: height)
                title = String(localized: verb)
                subtitle = String(localized: size)
            case .memory: title = String(localized: .dropPlaceBackWhereItWas); subtitle = name
            case .left: title = String(localized: .dropPlaceLeftHalf); subtitle = name
            case .right: title = String(localized: .dropPlaceRightHalf); subtitle = name
            case .fill: title = String(localized: .dropPlaceFillScreen); subtitle = name
            case .draw:
                title = String(localized: .dropPlaceDrawSize)
                subtitle = String(localized: .dropPlaceDrawSubtitle(width: width, height: height))
            }
        }
        return .init(frame: frame, title: title, subtitle: subtitle, tint: session.tint)
    }

    private func showOutline(_ outline: DropPlacementOverlayModel.Outline) {
        hideTask?.cancel(); hideTask = nil
        withAnimation(.easeOut(duration: 0.25)) { model.outline = outline }
        overlay.refresh()
    }

    /// Hands the pad off to the arrived window (fade while growing to 1.015), or fades it.
    private func finishPad(_ id: UUID, handoff: Bool) {
        guard let index = model.pads.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeOut(duration: handoff ? 0.45 : 0.3)) {
            model.pads[index].phase = handoff ? .handoff : .fading
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard let self else { return }
            model.pads.removeAll { $0.id == id }
            syncPanels()
        }
    }

    private func fadePads(for applicationID: String) {
        for pad in model.pads where pad.applicationID == applicationID && pad.phase == .waiting {
            finishPad(pad.id, handoff: false)
        }
    }

    /// Orders the panels out once their fade-outs have finished and nothing is left to draw.
    private func syncPanels() {
        guard model.isEmpty else { overlay.refresh(); return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled, let self else { return }
            hideTask = nil
            overlay.refresh()
        }
    }
}
