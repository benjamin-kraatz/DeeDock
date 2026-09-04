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
         organizer: any SemanticStackOrganizing) {
        let state = FolderStackState(folder: folder, organizer: organizer)
        self.state = state
        self.keyboard = keyboard
        popover = DockPopoverPanelController(anchor: anchor, keyboard: keyboard) { chrome in
            state.chrome = chrome
        } content: {
            FolderStackView(state: state, keyboard: keyboard)
        }
        popover.willClose = { [weak state] in state?.stop() }
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
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            close(returnFocus: false)
        } else if NSWorkspace.shared.open(entry.url) {
            close(returnFocus: false)
        } else {
            state.report(String(localized: .folderStackOpenFailed(itemName: entry.name))) { [weak self] in self?.open(entry) }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 48:
            state.presentationFocused.toggle()
        case 49 where state.presentationFocused:
            choosePresentation(by: 1)
        case 36 where !state.presentationFocused, 76 where !state.presentationFocused:
            state.openSelection()
        case 53:
            close(returnFocus: true)
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
            return false
        }
        return true
    }

    private func choosePresentation(by distance: Int) {
        let modes = FolderStackPresentation.allCases
        guard let current = modes.firstIndex(of: state.presentation) else { return }
        let next = min(max(current + distance, modes.startIndex), modes.index(before: modes.endIndex))
        state.choose(modes[next])
    }
}
