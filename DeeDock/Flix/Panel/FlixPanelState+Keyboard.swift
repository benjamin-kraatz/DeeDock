import AppKit
import Carbon

/// The panel's keys, offered every key-down before a view sees it.
///
/// While the search field has focus, only navigation, Return, Escape, and commands that never edit
/// text are taken; everything else reaches the field. Typing a character elsewhere starts a search
/// with it.
extension FlixPanelState {
    /// - Returns: True when the key was handled and must not reach the views.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if code == kVK_Escape { return escape() }
        // A sheet or dialog owns its own keys.
        if sheet != nil || confirmation != nil { return false }

        switch code {
        case kVK_DownArrow, kVK_UpArrow:
            moveSelection(by: code == kVK_DownArrow ? 1 : -1, extend: flags.contains(.shift))
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if searchFieldFocused, intelligence.searchesInPlainWords, case .idle = intelligence.query,
               !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                runSearch(searchText)
                return true
            }
            if flags.contains(.command) { reveal() } else { open() }
            return true
        default: break
        }

        if flags == [.command, .option], character == "c" {
            copyPaths()
            return true
        }
        if flags == .command {
            switch character {
            case "f": setSearchActive(true); return true
            case "k": toggleFlag(); return true
            case "d": addToFavorites(); return true
            case "r": askRobi(); return intelligence.canAskRobi
            case "c" where !searchFieldFocused: copy(); return true
            default: break
            }
            if code == kVK_Delete, !searchFieldFocused { trash(); return true }
            return false
        }
        guard !searchFieldFocused else { return false }
        if code == kVK_Space, flags.isEmpty || flags == .shift { quickLook(); return true }
        if code == kVK_Delete || code == kVK_ForwardDelete, flags.isEmpty { remove(); return true }
        // Type to search: a printable character without Command, Control, or Option.
        if flags.isDisjoint(with: [.command, .control, .option]), let typed = event.characters,
           typed.count == 1, let scalar = typed.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar), scalar.properties.isAlphabetic || scalar.properties.numericType != nil
            || CharacterSet.punctuationCharacters.contains(scalar) {
            setSearchActive(true)
            searchText += typed
            return true
        }
        return false
    }

    /// Escape peels back one layer: a dialog, a sheet, More like this, search, then the panel.
    private func escape() -> Bool {
        if confirmation != nil { confirmation = nil; return true }
        if sheet != nil { sheet = nil; return true }
        if intelligence.moreLikeThis != nil { intelligence.clearMoreLikeThis(); return true }
        if searchActive { setSearchActive(false); return true }
        close?(true)
        return true
    }
}
