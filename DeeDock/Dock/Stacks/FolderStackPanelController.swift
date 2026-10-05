import AppKit
import SwiftUI

/// Folder-specific behavior for one open stack: what its keys mean and what opening a child does.
/// The window, its dismissal monitors, and its animation belong to `DockPopoverPanelController`.
@MainActor
final class FolderStackPanelController {
    let state: FolderStackState
    private let popover: DockPopoverPanelController<FolderStackView>
    private let keyboard: Bool
    private var reveal: Task<Void, Never>?
    private var itemOpen: Task<Void, Never>?
    private var dismissed = false
    /// Runs after the window is ordered front, so a cancelled open is not treated as shown.
    var appeared: (() -> Void)?
    var closed: ((Bool) -> Void)? {
        get { popover.closed }
        set { popover.closed = newValue }
    }

    init(folder: FolderReference, anchor: DockPopoverAnchor, keyboard: Bool,
         organizer: any SemanticStackOrganizing, sort: FolderStackSort = .alphabetical) {
        let state = FolderStackState(folder: folder, sort: sort, organizer: organizer)
        self.state = state
        self.keyboard = keyboard
        popover = DockPopoverPanelController(anchor: anchor, keyboard: keyboard, clickFocus: true) { chrome in
            state.chrome = chrome
        } content: {
            FolderStackView(state: state, keyboard: keyboard)
        }
        popover.willClose = { [weak self] in
            guard let self else { return }
            dismissed = true
            reveal?.cancel()
            itemOpen?.cancel()
            state.stop()
        }
        popover.enableFileDrops()
        popover.dragEntered = { [weak state] info in
            guard let state, state.preview == nil else { return [] }
            let operation = state.dropOperation(info)
            state.dropTargeted = !operation.isEmpty
            state.dropTargetChanged(info, destination: state.directoryName)
            return operation
        }
        popover.dragExited = { [weak state] in
            state?.dropTargeted = false
            state?.dropTargetChanged(nil, destination: "")
        }
        popover.dragPerformed = { [weak state] info in
            state?.dropTargeted = false
            return state?.receive(info) ?? false
        }
        popover.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
    }

    func show() {
        dismissed = false
        state.start()
        reveal?.cancel()
        reveal = Task { [weak self] in
            guard let self else { return }
            guard await state.waitUntilOpen(), !Task.isCancelled, !dismissed else {
                if !dismissed { close(returnFocus: false) }
                return
            }
            if keyboard { state.selectedID = state.entries.first?.id }
            popover.show()
            appeared?()
            appeared = nil
        }
    }

    func update(_ anchor: DockPopoverAnchor) { popover.update(anchor) }

    func close(returnFocus: Bool) { popover.close(returnFocus: returnFocus) }

    func open(_ entry: FolderStackEntryReference) {
        if QuarantineStampController.shared.armed {
            QuarantineStampController.shared.stamp(id: entry.url.standardizedFileURL.path, url: entry.url, name: entry.name)
            return
        }
        guard !QuarantineStore.shared.blocks(entry.url) else {
            state.report(String(localized: .quarantineBlocked)) { }
            return
        }
        let path = entry.url.path
        let trigger = Analytics.trigger()
        itemOpen?.cancel()
        itemOpen = Task { [weak self] in
            let exists = await VolumeReads.run { FileManager.default.fileExists(atPath: path) }
            guard let self, !Task.isCancelled else { return }
            guard exists else {
                state.report(String(localized: .folderStackItemUnavailable(itemName: entry.name))) { [weak self] in self?.open(entry) }
                return
            }
            self.finishOpen(entry, trigger: trigger)
        }
    }

    private func finishOpen(_ entry: FolderStackEntryReference, trigger: AnalyticsTrigger) {
        if entry.isFolder {
            Analytics.track(.stackItemOpened(fileType: .folder, isFolder: true, trigger: trigger))
            state.navigate(to: entry.url)
        } else if NSWorkspace.shared.open(entry.url) {
            Analytics.track(.stackItemOpened(fileType: AnalyticsFileType(url: entry.url), isFolder: false,
                                             trigger: trigger))
            close(returnFocus: false)
        } else {
            state.report(String(localized: .folderStackOpenFailed(itemName: entry.name))) { [weak self] in self?.open(entry) }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            guard state.searchAvailable else { return false }
            state.focusSearch()
            return true
        }
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
        if state.searchFocused { return handleSearchKey(event) }
        switch event.keyCode {
        case 48:
            state.presentationFocused.toggle()
        case 49 where state.presentationFocused:
            choosePresentation(by: 1)
        case 49:
            state.previewSelection()
        case 36 where !state.presentationFocused, 76 where !state.presentationFocused:
            state.openSelection()
        case 53:
            if state.preview != nil { state.preview = nil }
            else { close(returnFocus: keyboard) }
        case 51:
            state.back()
        case 123 where state.presentationFocused:
            choosePresentation(by: -1)
        case 124 where state.presentationFocused:
            choosePresentation(by: 1)
        case 123, 124, 125, 126:
            moveSelection(by: arrowStep(event.keyCode))
        default:
            return beginTypeAhead(event)
        }
        return true
    }

    /// Keys while the field holds focus. Only selection and dismissal are claimed; everything else,
    /// Space and Delete included, belongs to the text being edited.
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            if !state.query.isEmpty { state.clearSearch() }
            else { state.focusSearch(false) }
        case 48:
            state.focusSearch(false)
        case 36, 76:
            state.openSelection()
        case 125, 126:
            moveSelection(by: arrowStep(event.keyCode))
        default:
            return false
        }
        return true
    }

    /// Typing over the listing starts a search, the way Finder does, instead of going nowhere.
    private func beginTypeAhead(_ event: NSEvent) -> Bool {
        guard state.searchAvailable, state.preview == nil, let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return false }
        state.beginTypeAhead(characters)
        return true
    }

    /// Grid arrows follow the columns that fit this panel. List arrows stay one item and wrap.
    private func arrowStep(_ keyCode: UInt16) -> Int {
        let columns = state.presentation == .grid ? gridColumns : 1
        return AdaptiveGridLayout.gridStep(keyCode: keyCode, columns: columns) ?? 0
    }

    private var gridColumns: Int {
        let pointer = state.chrome.edge.isVertical ? DockPopoverGeometry.pointerDepth : 0
        return AdaptiveGridLayout.columnCount(
            panelWidth: popover.panelWidth,
            minimum: FolderStackGridMetrics.minimumCell,
            spacing: FolderStackGridMetrics.columnSpacing,
            horizontalPadding: FolderStackGridMetrics.horizontalPadding,
            pointerInset: pointer)
    }

    /// Grid movement stops on the first and last item. List movement keeps its wrap.
    private func moveSelection(by delta: Int) {
        if state.presentation == .grid { state.selectClamped(by: delta) }
        else { state.select(by: delta) }
    }

    private func choosePresentation(by distance: Int) {
        let modes = FolderStackPresentation.allCases
        guard let current = modes.firstIndex(of: state.presentation) else { return }
        let next = min(max(current + distance, modes.startIndex), modes.index(before: modes.endIndex))
        state.choose(modes[next])
    }
}
