import AppKit

/// Owns the one native drag session shared by all docks. Panels retain only transient destination UI.
@MainActor
final class DockDragCoordinator: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("de.benjaminkraatz.DeeDock.application-drag")
    private var panels: [String: DockPanelController] = [:]
    private var sourceID: String?
    private var sourcePin: DockPin?
    private var token: String?
    private var nativeSession: NSDraggingSession?
    private var completion = DockDragCompletion()
    private var payload: DockExternalPayload = .checking
    private var pins: [DockPin] { payload.pins }
    private let documentDrag = DockDocumentDragState()
    private var nativeDisplayID: String?
    private var destinationID: String?
    private var trackingID: String?
    private var destinationIndex: Int?
    private var trashDestinationID: String?
    private var shelfDestinationID: String?
    /// Non-empty while the active external drag came out of DeeDock's own Shelf.
    private var shelfSourceIDs: [UUID] = []
    private var sourceBounds = CGRect.zero
    private var importTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var importSession = DockSession()
    private var pasteboardChange: Int?
    private var ignoredPasteboardChange: Int?
    private var rejected: Bool { payload.isRejected }
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
        begin(pin: .application(item.reference), icon: item.icon, from: displayID, view: view, event: event)
    }

    func begin(_ item: FolderDockItem, from displayID: String, view: NSView, event: NSEvent) {
        begin(pin: .folder(item.reference), icon: item.icon, from: displayID, view: view, event: event)
    }

    private func begin(pin: DockPin, icon: NSImage, from displayID: String, view: NSView, event: NSEvent) {
        guard let panel = panels[displayID], panel.store.canEditPins else { return }
        cancel()
        active = true; sourceID = displayID; sourcePin = pin
        payload = .selection(pins: [pin], documents: nil, stageableItems: nil)
        token = UUID().uuidString; sourceBounds = panel.restingDragBounds
        completion = DockDragCompletion()
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(token!, forType: Self.pasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: pasteboard)
        let dimension = min(view.bounds.width, view.bounds.height)
        dragItem.setDraggingFrame(CGRect(x: view.bounds.midX - dimension / 2, y: view.bounds.maxY - dimension,
                                        width: dimension, height: dimension), contents: icon)
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
        nativeDisplayID = displayID
        guard validates(info.draggingPasteboard) else { return [] }
        nativeDisplayID = displayID // Loading a new payload clears the preceding session.
        update(at: NSEvent.mouseLocation)
        if shelfDestinationID == displayID { return .copy }
        // Removing a staged reference is a discard, not a file operation, but the poof cursor is right.
        if trashDestinationID == displayID { return .delete }
        if documentDrag.displayID != nil {
            guard documentDrag.displayID == displayID else { return [] }
            return DockDocumentTarget.operation(allowed: info.draggingSourceOperationMask)
        }
        guard destinationID == displayID, destinationIndex != nil, !pins.isEmpty else { return [] }
        return sourceID == displayID ? .move : .copy
    }

    func perform(_ info: NSDraggingInfo, on displayID: String) -> Bool {
        guard !completion.committed, !completion.cancelled, validates(info.draggingPasteboard) else { return false }
        nativeDisplayID = displayID
        update(at: NSEvent.mouseLocation)
        if shelfDestinationID == displayID, let access = payload.stageableItems,
           let panel = panels[displayID] {
            completion.committed = true
            panel.store.stageOnShelf(access)
            cancel()
            return true
        }
        if trashDestinationID == displayID, let panel = panels[displayID] {
            // A Shelf item dropped on Trash gives up its reference. The file itself is untouched.
            if !shelfSourceIDs.isEmpty {
                completion.committed = true
                panel.store.removeFromShelf(ids: Set(shelfSourceIDs))
                cancel()
                return true
            }
            guard let access = payload.stageableItems else { return false }
            completion.committed = true
            panel.store.recycleToTrash(access)
            cancel()
            return true
        }
        if let documents = payload.documents, documentDrag.displayID != nil {
            guard documentDrag.displayID == displayID, let item = documentDrag.item,
                  let panel = panels[displayID],
                  !DockDocumentTarget.operation(allowed: info.draggingSourceOperationMask).isEmpty else { return false }
            completion.committed = true
            // The catalog retains the leases before clearing this drag's temporary state.
            panel.store.openDocuments(documents, with: item.reference)
            cancel()
            return true
        }
        guard !completion.cancelled, destinationID == displayID, let index = destinationIndex,
              let panel = panels[displayID], !pins.isEmpty else { return false }
        committing = true
        let success = panel.store.insertPins(pins, at: index)
        committing = false
        // A rejected save must not be reinterpreted as dragging out to unpin the source.
        completion.committed = true
        if sourceID == nil { cancel() } else { clearFeedback() }
        return success
    }

    func exited() {
        nativeDisplayID = nil
        documentDrag.clear()
        if active { update(at: NSEvent.mouseLocation) }
    }
    func geometryChanged() { if active { update(at: NSEvent.mouseLocation) } }

    func springTarget(_ info: NSDraggingInfo, on displayID: String) -> String? {
        guard !entered(info, on: displayID).isEmpty, payload.documents != nil else { return nil }
        return documentDrag.targetKey
    }

    func springActivate(_ info: NSDraggingInfo, on displayID: String) {
        guard springTarget(info, on: displayID) != nil, let panel = panels[displayID] else { return }
        documentDrag.activate(on: panel)
    }

    func springHighlight(_ info: NSDraggingInfo, on displayID: String) {
        guard let panel = panels[displayID] else { return }
        panel.interaction.springEmphasized = documentDrag.displayID == displayID && info.springLoadingHighlight == .emphasized
    }

    func externalEnded() { if sourceID == nil { cancel() } }

    private func validates(_ pasteboard: NSPasteboard) -> Bool {
        if let value = pasteboard.string(forType: Self.pasteboardType) {
            return active && token == value && sourceID != nil && !completion.cancelled
        }
        guard sourceID == nil else { return false }
        load(pasteboard)
        return active && !completion.cancelled && !completion.committed
    }

    private func load(_ pasteboard: NSPasteboard) {
        guard pasteboardChange != pasteboard.changeCount, ignoredPasteboardChange != pasteboard.changeCount else { return }
        // Never accept a stale or fabricated internal token as a Finder payload.
        guard pasteboard.string(forType: Self.pasteboardType) == nil else { return }
        cancel()
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !objects.isEmpty else { return }
        pasteboardChange = pasteboard.changeCount; active = true; completion = DockDragCompletion(); importSession = DockSession()
        shelfSourceIDs = (pasteboard.string(forType: ShelfDragSession.pasteboardType) ?? "")
            .split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        let generation = importSession.token
        let ownIdentifier = Bundle.main.bundleIdentifier ?? "de.benjaminkraatz.DeeDock"
        installMonitor()
        if pasteboard.pasteboardItems?.count != objects.count { payload = .rejected; return }
        // Acquire while the native destination still owns the user-granted pasteboard URLs.
        let access = DocumentResourceAccess(objects)
        importTask = Task { [weak self] in
            let worker = Task.detached {
                Result { try DockExternalPayload.read(access, excluding: ownIdentifier) }
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, importSession.accepts(generation), active else { return }
            switch result {
            case .success(let result): payload = result
            case .failure: payload = .rejected
            }
            importTask = nil
            update(at: NSEvent.mouseLocation)
        }
    }

    /// Which trailing utility tile the pointer is over, if the current payload may target it.
    /// Items already staged cannot be dropped back onto the Shelf, so that target is withheld.
    private func utilityTarget(at point: CGPoint, on panel: DockPanelController) -> DockUtilityDropTarget? {
        if panel.trashTarget(at: point) { return .trash }
        if shelfSourceIDs.isEmpty, panel.shelfTarget(at: point) { return .shelf }
        return nil
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
        destinationID = nil; destinationIndex = nil; trashDestinationID = nil; shelfDestinationID = nil
        let candidate = panels.values.first { $0.containsDragRegion(point) }
        trackingID = candidate?.store.displayID
        if sourceID == nil, payload.isReady, payload.stageableItems != nil,
           let candidate, candidate.store.displayID == nativeDisplayID,
           let utility = utilityTarget(at: point, on: candidate) {
            switch utility {
            case .trash: trashDestinationID = candidate.store.displayID
            case .shelf: shelfDestinationID = candidate.store.displayID
            }
            documentDrag.clear()
            for panel in panels.values {
                let targeted = panel === candidate
                panel.updateSectionDragHover(at: point, valid: false)
                panel.interaction.documentTargetID = nil
                panel.interaction.springEmphasized = false
                panel.interaction.trashTargeted = targeted && utility == .trash
                panel.interaction.shelfTargeted = targeted && utility == .shelf
                panel.setDragPresentation(proposal: nil, source: nil, targeted: targeted,
                    message: targeted ? utility.message(removingFromShelf: !shelfSourceIDs.isEmpty) : nil)
            }
            updateScrollTimer()
            return
        }
        panels.values.forEach { $0.interaction.trashTargeted = false; $0.interaction.shelfTargeted = false }
        if payload.documents != nil {
            let documentOwnsPresentation = documentDrag.update(
                at: point,
                candidate: candidate,
                nativeDisplayID: nativeDisplayID,
                panels: panels,
                presentsFallback: payload.presentsDocumentFallback
            )
            if documentOwnsPresentation { updateScrollTimer(); return }
        }
        for panel in panels.values {
            panel.updateSectionDragHover(at: point, valid: candidate === panel && !rejected && !pins.isEmpty && panel.store.canEditPins)
        }
        if let candidate, candidate.visibility.exposesContent, candidate.store.canEditPins, !rejected,
           !pins.isEmpty, let index = candidate.insertionIndex(at: point) {
            destinationID = candidate.store.displayID; destinationIndex = index
        }
        let overDock = panels.contains { id, panel in panel.protectsDragRemoval(at: point, isSource: id == sourceID) }
        let removing = sourcePin.map { pin in
            sourceID.flatMap { panels[$0] }?.store.pins.contains(where: { $0.id == pin.id }) == true
        } == true && !overDock && DockDragGeometry.distance(point, outside: sourceBounds) >= DockDragGeometry.removalDistance
        for (id, panel) in panels {
            let targeted = candidate === panel
            let proposal = id == destinationID ? DockDragProposal(pins: pins, index: destinationIndex!) : nil
            let message: LocalizedStringResource? = id == sourceID && removing ? .actionUnpin : (targeted
                ? (rejected || (!pins.isEmpty && !panel.store.canEditPins) ? .dragRejected
                    : (payload.isChecking ? .dragCheckingFiles
                        : (pins.isEmpty ? .dragDocumentTarget : (proposal == nil ? .dragPinnedSection : .dragPinHere))))
                : nil)
            panel.setDragPresentation(proposal: proposal, source: id == sourceID ? sourcePin?.id : nil,
                                      targeted: targeted, message: message)
        }
        nativeSession?.animatesToStartingPositionsOnCancelOrFail = !removing
        if let nativeSession, lastRemovalCue != removing {
            lastRemovalCue = removing
            nativeSession.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                guard let pin = self.sourcePin,
                      let icon = self.panels[self.sourceID ?? ""]?.store.entries.first(where: { $0.pin?.id == pin.id })?.icon else { return }
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
        let scrolling = payload.isReady ? (trackingID.flatMap { panels[$0] }?.dragScrollVelocity(at: NSEvent.mouseLocation) ?? 0) : 0
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
        if let sourceID, let sourcePin, let panel = panels[sourceID],
           completion.shouldUnpin(isPinned: panel.store.pins.contains { $0.id == sourcePin.id },
                                  distance: DockDragGeometry.distance(screenPoint, outside: sourceBounds),
                                  overDock: panels.contains { id, target in target.protectsDragRemoval(at: screenPoint, isSource: id == sourceID) }) {
            committing = true
            _ = panel.store.removePin(sourcePin.id)
            committing = false
        }
        cancel()
    }

    private func clearFeedback() {
        scrollTimer?.invalidate(); scrollTimer = nil
        documentDrag.clear()
        panels.values.forEach {
            $0.interaction.documentTargetID = nil
            $0.interaction.springEmphasized = false
            $0.interaction.trashTargeted = false
            $0.interaction.shelfTargeted = false
            $0.setDragPresentation(proposal: nil, source: nil, targeted: false, message: nil)
            $0.endSectionDrag()
        }
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
        nativeSession = nil; lastRemovalCue = nil; sourceID = nil; sourcePin = nil; token = nil
        payload = .checking; nativeDisplayID = nil; trackingID = nil; destinationID = nil; destinationIndex = nil
        trashDestinationID = nil; shelfDestinationID = nil; shelfSourceIDs = []
        if let pasteboardChange { ignoredPasteboardChange = pasteboardChange }
        pasteboardChange = nil
    }

    func stop() { cancel(); panels = [:] }
}
