import AppKit
import SwiftUI

/// Folder-specific behavior for one open stack: what its keys mean and what opening a child does.
/// The window, its dismissal monitors, and its animation belong to `DockPopoverPanelController`.
@MainActor
final class FolderStackPanelController {
    let state: FolderStackState
    private let popover: DockPopoverPanelController<FolderStackView>
    private let keyboard: Bool
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
        popover.willClose = { [weak state] in state?.stop() }
        popover.enableFileDrops()
        popover.dragEntered = { [weak state] info in
            guard let state, !state.copying, state.preview == nil,
                  FolderFileDrop.urls(info) != nil else { return [] }
            state.dropTargeted = true
            return .copy
        }
        popover.dragExited = { [weak state] in state?.dropTargeted = false }
        popover.dragPerformed = { [weak state] info in
            state?.dropTargeted = false
            return state?.receive(info) ?? false
        }
        popover.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
    }

    func show() {
        if keyboard { state.selectedID = state.entries.first?.id }
        popover.show()
        state.start()
    }

    func update(_ anchor: DockPopoverAnchor) { popover.update(anchor) }

    func close(returnFocus: Bool) { popover.close(returnFocus: returnFocus) }

    func open(_ entry: FolderStackEntryReference) {
        guard FileManager.default.fileExists(atPath: entry.url.path) else {
            state.report(String(localized: .folderStackItemUnavailable(itemName: entry.name))) { [weak self] in self?.open(entry) }
            return
        }
        if entry.isFolder {
            state.navigate(to: entry.url)
        } else if NSWorkspace.shared.open(entry.url) {
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
        case 123:
            state.select(by: -1)
        case 124:
            state.select(by: 1)
        case 125:
            state.select(by: state.presentation == .grid ? 5 : 1)
        case 126:
            state.select(by: state.presentation == .grid ? -5 : -1)
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
        case 125:
            state.select(by: 1)
        case 126:
            state.select(by: -1)
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

    private func choosePresentation(by distance: Int) {
        let modes = FolderStackPresentation.allCases
        guard let current = modes.firstIndex(of: state.presentation) else { return }
        let next = min(max(current + distance, modes.startIndex), modes.index(before: modes.endIndex))
        state.choose(modes[next])
    }
}
