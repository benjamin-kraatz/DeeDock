import AppKit
import SwiftUI

/// A drag of files or folders (from the Hub or another app) while it is over the Hub.
struct HubFilesSidebarItemDrag {
    /// `draggingSequenceNumber` of the session, so a new session starts fresh.
    let sequence: Int
    let sources: [URL]
    /// The sources that can become sidebar rows.
    let folders: [URL]
    /// The Favorites base layout, measured the first time the drag reaches the sidebar.
    var layout: HubFilesSidebarDropLayout?
    var target: HubFilesSidebarDropLayout.Target = .none
    /// Counts sidebar updates, so an exit followed by an enter on the next row isn't a real exit.
    var serial = 0
    /// Ends the session if the drag ends somewhere the Hub isn't told about.
    var watchdog: Task<Void, Never>?
}

/// A Favorites row being dragged to a new position or out of the sidebar.
struct HubFilesSidebarReorder {
    let id: HubFilesSidebarEntryID
    let sourceIndex: Int
    /// The pointer's offset from the row's origin (screen coordinates), kept while it moves.
    let grabOffset: CGSize
    /// The row's frame when it lifted, in screen coordinates.
    let rowFrame: CGRect
    /// The same frame in the drop layout's space (the Favorites section, top-down).
    let layoutFrame: CGRect
    let layout: HubFilesSidebarDropLayout
    var removing = false
}

extension HubFilesSidebarModel {
    // MARK: Item drags

    /// A drag that started in the Hub. Shows the end slot right away when it carries folders.
    func itemDragBegan(sequence: Int, urls: [URL]) {
        startItemDrag(sequence: sequence, sources: urls)
    }

    /// The drag session that started in the Hub ended, wherever it was dropped.
    func itemDragEnded(sequence: Int) {
        guard itemDrag?.sequence == sequence else { return }
        endItemDrag()
    }

    /// Any Files drop target saw a drag. Starts a session for drags from other apps, so the end
    /// slot appears as soon as a folder enters the Hub, not only once it reaches the sidebar.
    func itemDragEntered(_ info: NSDraggingInfo) {
        guard itemDrag?.sequence != info.draggingSequenceNumber,
              info.draggingPasteboard.string(forType: DockDragCoordinator.pasteboardType) == nil else { return }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        startItemDrag(sequence: info.draggingSequenceNumber, sources: urls)
    }

    /// The drag moved over a Favorites row, slot, end slot, header, or the gaps between them.
    /// Picks the target, opens or moves the slot, and names the action under the pointer.
    func itemDragUpdated(_ info: NSDraggingInfo, in view: NSView) -> NSDragOperation {
        itemDragEntered(info)
        guard var drag = itemDrag, let window = view.window else { return [] }
        if drag.layout == nil { drag.layout = makeLayout(lifted: nil, sources: drag.sources) }
        guard let layout = drag.layout else { return [] }
        let point = window.convertPoint(toScreen: info.draggingLocation)
        guard let y = layoutY(atScreen: point) else { return [] }
        let target = layout.target(at: y, slot: currentSlot(in: layout), mode: .items(canInsert: !drag.folders.isEmpty))
        drag.target = target
        drag.serial += 1
        itemDrag = drag
        showItemTarget(target, folders: drag.folders)
        let operation = operation(for: target, drag: drag, info: info)
        showLabel(action(for: target, operation: operation), at: point)
        return operation
    }

    /// The drag left a sidebar target. Moving straight onto the next row sends exit then enter in
    /// the same turn, so the targets clear only if no update follows.
    func itemDragExited() {
        guard let serial = itemDrag?.serial else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let drag = self.itemDrag, drag.serial == serial else { return }
            self.itemDrag?.target = .none
            self.showItemTarget(.none, folders: drag.folders)
            self.labelWindow.hide()
        }
    }

    /// Spring-loading opens a row only while a file drop would land in it.
    func springLoads(_ id: HubFilesSidebarEntryID) -> Bool {
        intoTarget == id
    }

    /// Adds the dragged folders at the slot, or moves or copies the items into the targeted row.
    func performItemDrop(_ info: NSDraggingInfo, in view: NSView) -> Bool {
        let operation = itemDragUpdated(info, in: view)
        guard let drag = itemDrag, !operation.isEmpty else {
            endItemDrag()
            return false
        }
        switch drag.target {
        case .insert(let index):
            settleDragImage(info, in: view)
            // The new rows take the slot's place in the same frame, so nothing moves.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            let result = withTransaction(transaction) {
                slotIndex = nil
                slotPreview = nil
                if endSlot?.isTargeted == true { endSlot = nil }
                return store.insert(drag.folders, at: index)
            }
            flash(result.ids, .arrival)
            if result.added.isEmpty {
                Analytics.track(.hubFilesSidebarEdited(.reorder, method: .drag, itemCount: result.ids.count))
            } else {
                Analytics.track(.hubFilesSidebarEdited(.add, method: .drag, itemCount: result.added.count))
            }
            endItemDrag()
            return true
        case .into(let index):
            defer { endItemDrag() }
            guard store.entries.indices.contains(index), let files,
                  let destination = store.folderURL(for: store.entries[index]) else { return false }
            return files.performDrop(sources: drag.sources, destination: destination,
                                     optionHeld: NSEvent.modifierFlags.contains(.option),
                                     sourceMask: info.draggingSourceOperationMask)
        case .none:
            endItemDrag()
            return false
        }
    }

    // MARK: Reordering

    /// A Favorites row started moving: it lifts into an overlay and its slot stays open under it.
    ///
    /// - Returns: False when it can't start yet: a row released a moment ago was still gliding
    ///   into place (it lands now, and its row reappears on the next layout pass), or some row
    ///   has no laid-out view to measure. The caller retries on the next pointer move.
    @discardableResult
    func beginReorder(_ id: HubFilesSidebarEntryID, pointer: CGPoint, rowFrame: CGRect) -> Bool {
        if pendingSettle != nil {
            finishPendingSettle()
            return false
        }
        guard reorder == nil, let index = store.index(of: id), let entry = store.entry(id),
              let layout = makeLayout(lifted: id, sources: []),
              let layoutFrame = rowViews[id]?.view.flatMap(layoutRect(of:)) else { return false }
        reorder = HubFilesSidebarReorder(
            id: id, sourceIndex: index,
            grabOffset: CGSize(width: pointer.x - rowFrame.minX, height: pointer.y - rowFrame.minY),
            rowFrame: rowFrame, layoutFrame: layoutFrame, layout: layout)
        problem = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            slotHeight = rowFrame.height
            slotPreview = preview(for: entry)
            slotIndex = index
            liftedID = id
        }
        showLiftedRow(entry, removing: false, pointer: pointer)
        files?.shell?.beginHold(.drag)
        return true
    }

    /// The lifted row moved. Far enough outside the sidebar it would be removed; just outside, it
    /// would go back where it was; inside, the slot follows it.
    func updateReorder(pointer: CGPoint) {
        guard var drag = reorder, let entry = store.entry(drag.id) else { return }
        let sidebar = sidebarView?.screenFrame
        let removing = sidebar.map { !$0.insetBy(dx: -30, dy: -30).contains(pointer) } ?? false
        var index = drag.sourceIndex
        if let sidebar, sidebar.contains(pointer), let pointerY = layoutY(atScreen: pointer) {
            let target = drag.layout.reorderIndex(at: pointerY, slot: currentSlot(in: drag.layout))
            index = target == drag.sourceIndex + 1 ? drag.sourceIndex : target
        }
        if removing != drag.removing {
            drag.removing = removing
            (removing ? NSCursor.disappearingItem : NSCursor.arrow).set()
        }
        reorder = drag
        let slot: Int? = removing ? nil : index
        if slot != slotIndex { HubFilesMotion.withLayoutAnimation { slotIndex = slot } }
        showLiftedRow(entry, removing: removing, pointer: pointer)
    }

    /// The row was released: removed with a poof, or settled into its slot.
    func endReorder(pointer: CGPoint) {
        guard let drag = reorder else { return }
        reorder = nil
        NSCursor.arrow.set()
        files?.shell?.endHold(.drag)
        if drag.removing {
            liftWindow.hide()
            showPoof(at: pointer)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                liftedID = nil
                slotPreview = nil
            }
            // The gap already closed while the row hovered outside.
            remove([drag.id], method: .dragOut, animated: false)
            return
        }
        settle(drag, at: slotIndex ?? drag.sourceIndex)
    }

    /// Escape during a reorder: the row goes back where it was.
    func cancelReorder() {
        guard let drag = reorder else { return }
        reorder = nil
        NSCursor.arrow.set()
        files?.shell?.endHold(.drag)
        HubFilesMotion.withLayoutAnimation { slotIndex = drag.sourceIndex }
        settle(drag, at: drag.sourceIndex)
    }

    // MARK: Helpers

    /// Glides the lifted row onto its slot, then swaps it for the real row at that position.
    private func settle(_ drag: HubFilesSidebarReorder, at index: Int) {
        settleSerial += 1
        let serial = settleSerial
        // Runs once: when the glide ends, or earlier if another drag starts first.
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.pendingSettle?.serial == serial else { return }
            self.pendingSettle = nil
            self.liftWindow.hide()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.liftedID = nil
                self.slotIndex = nil
                self.slotPreview = nil
                if index != drag.sourceIndex { self.store.move(drag.id, to: index) }
            }
            if index != drag.sourceIndex {
                Analytics.track(.hubFilesSidebarEdited(.reorder, method: .drag, itemCount: 1))
            }
        }
        pendingSettle = (serial, finish)
        // Aim for where the slot ends up, from the base layout: its view may still be springing
        // there, so its current frame isn't reliable yet.
        let target = CGRect(x: drag.layoutFrame.minX, y: drag.layout.slotTop(for: index),
                            width: drag.layoutFrame.width, height: drag.layoutFrame.height)
        guard !HubFilesMotion.reduceMotion, let slot = screenRect(fromLayout: target) else {
            finish()
            return
        }
        liftWindow.move(to: Self.liftFrame(rowOrigin: slot.origin, rowSize: drag.rowFrame.size),
                        duration: 0.22, completion: finish)
    }

    /// Lands a row that is still gliding into its slot right away, on a fresh overlay window so
    /// the unfinished frame animation can't move the next lifted row.
    func finishPendingSettle() {
        guard let pending = pendingSettle else { return }
        pending.finish()
        liftWindow = HubFilesOverlayWindow()
    }

    private func startItemDrag(sequence: Int, sources: [URL]) {
        itemDrag?.watchdog?.cancel()
        let folders = Self.addableFolders(sources)
        var drag = HubFilesSidebarItemDrag(sequence: sequence, sources: sources, folders: folders)
        // Drags that end somewhere the Hub never hears about (over another app, or cancelled
        // outside it) are noticed by the released mouse button. Checked only while a drag is live.
        drag.watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self?.endItemDrag()
                    return
                }
            }
        }
        itemDrag = drag
        let end = folders.isEmpty ? nil : EndSlot(folderCount: folders.count, isTargeted: false)
        if end != endSlot { HubFilesMotion.withLayoutAnimation { endSlot = end } }
    }

    /// Clears every drag affordance. The end slot collapses on the layout spring.
    func endItemDrag() {
        itemDrag?.watchdog?.cancel()
        itemDrag = nil
        labelWindow.hide()
        guard slotIndex != nil || endSlot != nil || intoTarget != nil else { return }
        HubFilesMotion.withLayoutAnimation {
            slotIndex = nil
            slotPreview = nil
            intoTarget = nil
            endSlot = nil
        }
    }

    private func showItemTarget(_ target: HubFilesSidebarDropLayout.Target, folders: [URL]) {
        var slot: Int?
        var into: HubFilesSidebarEntryID?
        var endTargeted = false
        switch target {
        case .insert(let index):
            if endSlot != nil, index >= store.entries.count { endTargeted = true } else { slot = index }
        case .into(let index):
            into = store.entries.indices.contains(index) ? store.entries[index].id : nil
        case .none:
            break
        }
        let preview = folders.isEmpty ? nil : SlotPreview(symbolName: "folder", title: Self.title(for: folders))
        if intoTarget != into { intoTarget = into }
        if slotPreview != preview { slotPreview = preview }
        if slotHeight != HubFilesMetrics.rowHeight { slotHeight = HubFilesMetrics.rowHeight }
        guard slot != slotIndex || (endSlot.map { $0.isTargeted != endTargeted } ?? false) else { return }
        HubFilesMotion.withLayoutAnimation {
            slotIndex = slot
            endSlot?.isTargeted = endTargeted
        }
    }

    private func operation(for target: HubFilesSidebarDropLayout.Target, drag: HubFilesSidebarItemDrag,
                           info: NSDraggingInfo) -> NSDragOperation {
        switch target {
        case .insert:
            // Adding to the sidebar touches no files. Copy shows the plus badge, which reads as "add".
            let mask = info.draggingSourceOperationMask
            for candidate: NSDragOperation in [.copy, .generic, .link] where mask.contains(candidate) { return candidate }
            return []
        case .into(let index):
            guard let files, store.entries.indices.contains(index),
                  let destination = store.folderURL(for: store.entries[index]) else { return [] }
            return files.dropOperation(sources: drag.sources, destination: destination,
                                       optionHeld: NSEvent.modifierFlags.contains(.option),
                                       sourceMask: info.draggingSourceOperationMask)
        case .none:
            return []
        }
    }

    private func action(for target: HubFilesSidebarDropLayout.Target, operation: NSDragOperation) -> HubFilesSidebarAction? {
        guard !operation.isEmpty else { return nil }
        switch target {
        case .insert: return .add
        case .into(let index):
            let name = store.entries.indices.contains(index) ? store.title(for: store.entries[index]) : ""
            return operation == .move ? .move(name) : .copy(name)
        case .none: return nil
        }
    }

    /// The open slot as the layout sees it: where it starts in the base layout and its height.
    private func currentSlot(in layout: HubFilesSidebarDropLayout) -> HubFilesSidebarDropLayout.Slot? {
        slotIndex.map { .init(index: $0, top: layout.slotTop(for: $0), height: slotHeight) }
    }

    /// Measures the Favorites rows for hit testing, in the Favorites section's own top-down space.
    ///
    /// The section scrolls with the sidebar, and pointers are converted into the same space on
    /// every update (`layoutY(atScreen:)`), so the layout stays right if the sidebar scrolls
    /// during a drag. With `lifted`, that row is left out and the rows below it move up by its
    /// height: the base layout the reorder slot (opened at the lifted row's place) is mapped against.
    func makeLayout(lifted: HubFilesSidebarEntryID?, sources: [URL]) -> HubFilesSidebarDropLayout? {
        guard favoritesView?.window != nil else { return nil }
        var rows: [HubFilesSidebarDropLayout.Row] = []
        var shift: CGFloat = 0
        for (index, entry) in store.entries.enumerated() {
            // A row without a laid-out view (just restored, or not rebuilt yet) would leave a hole
            // that reads as "insert at the end"; measure again on the next update instead.
            guard let frame = rowViews[entry.id]?.view.flatMap(layoutRect(of:)) else { return nil }
            if entry.id == lifted {
                shift = frame.height
                continue
            }
            let accepts = !sources.isEmpty && store.folderURL(for: entry).map {
                HubFileTransferQueue.isValidDrop(sources: sources, destination: $0)
            } == true
            rows.append(.init(index: index, top: frame.minY - shift, bottom: frame.maxY - shift, acceptsInto: accepts))
        }
        let top: CGFloat = 0
        let last = rows.last?.bottom ?? top + HubFilesSidebarMetrics.endZone
        let tail = endSlot == nil ? HubFilesSidebarMetrics.endZone
            : HubFilesSidebarMetrics.endSlotSpacing + HubFilesMetrics.rowHeight + HubFilesSidebarMetrics.endZone / 2
        return HubFilesSidebarDropLayout(rows: rows, count: store.entries.count, top: top, bottom: last + tail)
    }

    /// A screen point as a top-down distance in the Favorites section, the drop layout's space.
    func layoutY(atScreen point: CGPoint) -> CGFloat? {
        guard let favorites = favoritesView, let window = favorites.window else { return nil }
        return favorites.convert(window.convertPoint(fromScreen: point), from: nil).y
    }

    /// A view's frame in the drop layout's space. The Favorites anchor is flipped, so y grows down.
    private func layoutRect(of view: NSView) -> CGRect? {
        guard let favorites = favoritesView, view.window != nil, view.window === favorites.window else { return nil }
        return favorites.convert(view.bounds, from: view)
    }

    /// A rect in the drop layout's space, in screen coordinates.
    private func screenRect(fromLayout rect: CGRect) -> CGRect? {
        guard let favorites = favoritesView, let window = favorites.window else { return nil }
        return window.convertToScreen(favorites.convert(rect, to: nil))
    }

    func preview(for entry: HubFilesSidebarEntry) -> SlotPreview {
        SlotPreview(symbolName: Self.symbolName(for: entry), title: store.title(for: entry))
    }

    static func symbolName(for entry: HubFilesSidebarEntry) -> String {
        switch entry {
        case .place(let place): place.symbolName
        case .folder: "folder"
        }
    }

    /// The slot's title: the folder's name, or "3 folders".
    private static func title(for folders: [URL]) -> String {
        guard folders.count != 1, !folders.isEmpty else {
            return folders.first.map { FileManager.default.displayName(atPath: FilePathCopy.path(of: $0)) } ?? ""
        }
        return String(localized: .hubFilesSidebarFolderCount(folders.count))
    }

    /// Lets the system drag image shrink into the slot on drop instead of snapping back.
    private func settleDragImage(_ info: NSDraggingInfo, in view: NSView) {
        guard !HubFilesMotion.reduceMotion, let window = view.window,
              let target = (endSlot?.isTargeted == true ? endSlotView : slotView)?.screenFrame else { return }
        let local = view.convert(window.convertFromScreen(target), from: nil)
        let glyph = CGRect(x: local.minX + 10, y: local.midY - 9.5, width: 19, height: 19)
        info.animatesToDestination = true
        info.enumerateDraggingItems(options: [], for: view, classes: [NSURL.self], searchOptions: [:]) { item, _, _ in
            item.draggingFrame = glyph
        }
    }
}
