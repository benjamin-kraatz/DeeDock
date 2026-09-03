import AppKit

/// Owns the one native drag session shared by all docks. Panels retain only transient destination UI.
@MainActor
final class DockDragCoordinator: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("de.benjaminkraatz.DeeDock.application-drag")
    private var panels: [String: DockPanelController] = [:]
    private var sourceID: String?
    private var reference: ApplicationReference?
    private var token: String?
    private var nativeSession: NSDraggingSession?
    private var completion = DockDragCompletion()
    private var references: [ApplicationReference] = []
    private var destinationID: String?
    private var trackingID: String?
    private var destinationIndex: Int?
    private var sourceBounds = CGRect.zero
    private var importTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var importSession = DockSession()
    private var pasteboardChange: Int?
    private var ignoredPasteboardChange: Int?
    private var rejected = false
    private var active = false
    private var preparingSource = false
    var isDragging: Bool { active || preparingSource }

    func trackSource(_ tracking: Bool) { preparingSource = tracking }
    private var updating = false
    private var cancelling = false
    private var lastRemovalCue: Bool?
    private var monitor: Any?
    private var scrollTimer: Timer?
    private(set) var committing = false

    func setPanels(_ panels: [String: DockPanelController]) { self.panels = panels }

    /// Starts a private app-reference drag; no file representation is exported to other applications.
    func begin(_ item: DockItem, from displayID: String, view: NSView, event: NSEvent) {
        guard let panel = panels[displayID], panel.store.canEditPins else { return }
        cancel()
        active = true; sourceID = displayID; reference = item.reference
        references = [item.reference]; token = UUID().uuidString; sourceBounds = panel.restingDragBounds
        completion = DockDragCompletion()
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(token!, forType: Self.pasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: pasteboard)
        let dimension = min(view.bounds.width, view.bounds.height)
        dragItem.setDraggingFrame(CGRect(x: view.bounds.midX - dimension / 2, y: view.bounds.maxY - dimension,
                                        width: dimension, height: dimension), contents: item.icon)
        installMonitor()
        nativeSession = view.beginDraggingSession(with: [dragItem], event: event, source: self)
        nativeSession?.animatesToStartingPositionsOnCancelOrFail = true
        update(at: NSEvent.mouseLocation)
    }

    /// Pointer policy reveals hidden docks first; native destination entry then validates the current payload.
    func observe(_ event: NSEvent) {
        if event.type == .leftMouseDragged {
            if active { update(at: NSEvent.mouseLocation) }
        } else if event.type == .leftMouseUp, active {
            completion.released = true
            if sourceID == nil {
                // Let native performDragOperation commit before the next main-loop turn clears feedback.
                let generation = importSession.token
                cleanupTask?.cancel()
                cleanupTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard let self, importSession.accepts(generation), sourceID == nil else { return }
                    cancel()
                }
            }
        }
    }

    func entered(_ info: NSDraggingInfo, on displayID: String) -> NSDragOperation {
        guard validates(info.draggingPasteboard) else { return [] }
        update(at: NSEvent.mouseLocation)
        guard destinationID == displayID, destinationIndex != nil, !references.isEmpty else { return [] }
        return sourceID == displayID ? .move : .copy
    }

    func perform(_ info: NSDraggingInfo, on displayID: String) -> Bool {
        guard validates(info.draggingPasteboard) else { return false }
        update(at: NSEvent.mouseLocation)
        guard !completion.cancelled, destinationID == displayID, let index = destinationIndex,
              let panel = panels[displayID], !references.isEmpty else { return false }
        committing = true
        let success = panel.store.insertPins(references, at: index)
        committing = false
        // A rejected save must not be reinterpreted as dragging out to unpin the source.
        completion.committed = true
        if sourceID == nil { cancel() } else { clearFeedback() }
        return success
    }

    func exited() { if active { update(at: NSEvent.mouseLocation) } }
    func externalEnded() { if sourceID == nil { cancel() } }

    private func validates(_ pasteboard: NSPasteboard) -> Bool {
        if let value = pasteboard.string(forType: Self.pasteboardType) {
            return active && token == value && sourceID != nil && !completion.cancelled
        }
        guard sourceID == nil else { return false }
        load(pasteboard)
        return active && !rejected
    }

    private func load(_ pasteboard: NSPasteboard) {
        guard pasteboardChange != pasteboard.changeCount, ignoredPasteboardChange != pasteboard.changeCount else { return }
        // Never accept a stale or fabricated internal token as a Finder payload.
        guard pasteboard.string(forType: Self.pasteboardType) == nil else { return }
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !objects.isEmpty else { return }
        cancel()
        pasteboardChange = pasteboard.changeCount; active = true; completion = DockDragCompletion(); importSession = DockSession()
        let generation = importSession.token
        let ownIdentifier = Bundle.main.bundleIdentifier ?? "de.benjaminkraatz.DeeDock"
        installMonitor()
        if pasteboard.pasteboardItems?.count != objects.count { rejected = true; return }
        importTask = Task { [weak self] in
            let worker = Task.detached {
                Result { try DockApplicationImporter.read(objects, excluding: ownIdentifier) }
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, importSession.accepts(generation), active else { return }
            switch result {
            case .success(let apps): references = DockOrdering.unique(apps)
            case .failure: rejected = true
            }
            importTask = nil
            update(at: NSEvent.mouseLocation)
        }
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp { completion.released = true }
            if event.type == .keyDown, event.keyCode == 53 {
                completion.cancelled = true
                nativeSession?.animatesToStartingPositionsOnCancelOrFail = true
                clearFeedback()
            }
            return event // AppKit must still receive Escape to terminate its native session.
        }
    }

    private func update(at point: CGPoint) {
        guard active, !updating, !completion.cancelled, !completion.committed else { return }
        updating = true
        defer { updating = false }
        destinationID = nil; destinationIndex = nil
        let candidate = panels.values.first { $0.containsDragRegion(point) }
        trackingID = candidate?.store.displayID
        if let candidate, candidate.visibility.exposesContent, candidate.store.canEditPins, !rejected,
           !references.isEmpty, let index = candidate.insertionIndex(at: point) {
            destinationID = candidate.store.displayID; destinationIndex = index
        }
        let overDock = panels.contains { id, panel in panel.protectsDragRemoval(at: point, isSource: id == sourceID) }
        let removing = reference.map { ref in
            sourceID.flatMap { panels[$0] }?.store.pins.contains(where: { $0.id == ref.id }) == true
        } == true && !overDock && DockDragGeometry.distance(point, outside: sourceBounds) >= DockDragGeometry.removalDistance
        for (id, panel) in panels {
            let targeted = candidate === panel
            let proposal = id == destinationID ? DockDragProposal(references: references, index: destinationIndex!) : nil
            let message: LocalizedStringResource? = id == sourceID && removing ? .actionUnpin : (targeted
                ? (rejected || !panel.store.canEditPins ? .dragRejected : (references.isEmpty ? .dragCheckingApps : (proposal == nil ? .dragPinnedSection : .dragPinHere)))
                : nil)
            panel.setDragPresentation(proposal: proposal, source: id == sourceID ? reference?.id : nil,
                                      targeted: targeted, message: message)
        }
        nativeSession?.animatesToStartingPositionsOnCancelOrFail = !removing
        if let nativeSession, lastRemovalCue != removing {
            lastRemovalCue = removing
            nativeSession.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                guard let icon = self.reference.flatMap({ ref in self.panels[self.sourceID ?? ""]?.store.items.first { $0.id == ref.id }?.icon }) else { return }
                let imageSize = item.draggingFrame.size
                item.imageComponentsProvider = {
                    let component = NSDraggingImageComponent(key: .icon)
                    component.contents = icon
                    component.frame = CGRect(origin: .zero, size: imageSize)
                    if !removing { return [component] }
                    let label = NSDraggingImageComponent(key: .label)
                    let text = String(localized: .actionUnpin) as NSString
                    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
                    let size = text.size(withAttributes: attributes)
                    let image = NSImage(size: CGSize(width: size.width + 12, height: size.height + 6))
                    image.lockFocus()
                    NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: CGRect(origin: .zero, size: image.size), xRadius: 5, yRadius: 5).fill()
                    text.draw(at: CGPoint(x: 6, y: 3), withAttributes: attributes)
                    image.unlockFocus()
                    label.contents = image; label.frame = CGRect(x: 0, y: -image.size.height - 4, width: image.size.width, height: image.size.height)
                    return [component, label]
                }
            }
        }
        updateScrollTimer()
    }

    private func updateScrollTimer() {
        let scrolling = !rejected && !references.isEmpty ? (trackingID.flatMap { panels[$0] }?.dragScrollVelocity(at: NSEvent.mouseLocation) ?? 0) : 0
        guard scrolling != 0 else { scrollTimer?.invalidate(); scrollTimer = nil; return }
        guard scrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active, let id = self.trackingID, let panel = self.panels[id] else { return }
                panel.scrollDuringDrag(at: NSEvent.mouseLocation, elapsed: 1.0 / 60)
                self.update(at: NSEvent.mouseLocation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard session === nativeSession else { return }; update(at: screenPoint)
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard session === nativeSession else { return }
        if let event = NSApp.currentEvent {
            if event.type == .leftMouseUp { completion.released = true }
            if event.type == .keyDown, event.keyCode == 53 { completion.cancelled = true }
        }
        if let sourceID, let reference, let panel = panels[sourceID],
           completion.shouldUnpin(isPinned: panel.store.pins.contains { $0.id == reference.id },
                                  distance: DockDragGeometry.distance(screenPoint, outside: sourceBounds),
                                  overDock: panels.contains { id, target in target.protectsDragRemoval(at: screenPoint, isSource: id == sourceID) }) {
            committing = true
            _ = panel.store.removePin(reference.id)
            committing = false
        }
        cancel()
    }

    private func clearFeedback() {
        scrollTimer?.invalidate(); scrollTimer = nil
        panels.values.forEach { $0.setDragPresentation(proposal: nil, source: nil, targeted: false, message: nil) }
    }

    /// Invalidates late imports and native completion callbacks without committing an edit.
    func cancel() {
        guard !cancelling else { return }
        cancelling = true
        defer { cancelling = false }
        completion.cancelled = true
        active = false; preparingSource = false; importSession.stop()
        importTask?.cancel(); importTask = nil
        cleanupTask?.cancel(); cleanupTask = nil
        clearFeedback()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        nativeSession = nil; lastRemovalCue = nil; sourceID = nil; reference = nil; token = nil
        references = []; trackingID = nil; destinationID = nil; destinationIndex = nil; rejected = false
        if let pasteboardChange { ignoredPasteboardChange = pasteboardChange }
        pasteboardChange = nil
    }

    func stop() { cancel(); panels = [:] }
}
