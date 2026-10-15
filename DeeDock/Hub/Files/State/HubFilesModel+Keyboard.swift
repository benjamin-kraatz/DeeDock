import AppKit

/// Keyboard handling for the Files tab, called by the shell for every key-down while visible.
extension HubFilesModel {
    private enum Key {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
    }

    func handleKeyDown(_ event: NSEvent, fromSearchField: Bool) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let key = event.specialKey
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // An open rename field owns typing; only Return and Escape end it.
        if let pane = renamingPane {
            if event.keyCode == Key.escape { cancelRename(in: pane); return true }
            if key == .carriageReturn || key == .enter { commitRename(in: pane); return true }
            return false
        }

        // Searching with a picture: ⌘V pastes one, ⌘⇧L finds files like the selected result or browser file, wherever
        // the focus is.
        if flags == .command, character == "v", pastePicture() { return true }
        if flags == [.command, .shift], character == "l", selectionSimilarAvailability != .hidden {
            findSimilarForSelection()
            return true
        }

        if fromSearchField {
            if isPictureSearch, flags.isEmpty {
                // ⌫ in the empty field takes the picture out and brings the words back; Escape clears both.
                if event.keyCode == Key.delete, query.isEmpty { removePicture(restoringWords: true); return true }
                if event.keyCode == Key.escape { removePicture(restoringWords: false); return true }
            }
            return handleSearchFieldKey(key, shift: shift, flags: flags)
        }

        if event.keyCode == Key.escape {
            if quickLook.isVisible { quickLook.close(); return true }
            if isPictureSearch { removePicture(restoringWords: false); return true }
            // The shell clears the query or closes the Hub.
            return false
        }

        if command, let handled = handleCommand(character: character, key: key, flags: flags) { return handled }

        if isSearching { return handleResultsKey(key, character: character, shift: shift, flags: flags, event: event) }
        return handlePaneKey(key, character: character, shift: shift, flags: flags, event: event)
    }

    // MARK: Search field

    /// ↓ moves from the header field into the content; ↑/↓ and Return work on results.
    private func handleSearchFieldKey(_ key: NSEvent.SpecialKey?, shift: Bool, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.subtracting(.shift).isEmpty else { return false }
        switch key {
        case .downArrow:
            if isSearching {
                moveSearchSelection(by: 1, extending: shift)
            } else if activePane.selection.isEmpty {
                activePane.moveSelection(by: 1, extending: false)
            }
            shell?.focusContent()
            return true
        case .upArrow where isSearching:
            moveSearchSelection(by: -1, extending: shift)
            return true
        case .carriageReturn, .enter:
            guard isSearching else { return false }
            if searchSelection.isEmpty, lookoutSelection == nil {
                openFirstSearchResult()
            } else {
                openSelection()
            }
            return true
        default:
            return false
        }
    }

    // MARK: Command shortcuts

    /// ⌘ shortcuts shared by panes and results. Returns nil when the event is not one of them.
    private func handleCommand(character: String, key: NSEvent.SpecialKey?, flags: NSEvent.ModifierFlags) -> Bool? {
        let option = flags.contains(.option), shift = flags.contains(.shift)
        if flags.contains(.control) {
            // ⌃⌘T adds the selected folders to the sidebar, as in Finder. Checked first: without
            // Control the same key opens a tab.
            guard character == "t", !option, !shift else { return nil }
            addSelectionToSidebar()
            return true
        }
        // ⌘Z undoes a sidebar removal while its toast offers it; otherwise it isn't ours.
        if character == "z", !option, !shift, sidebar.undoRemoval() { return true }
        switch (character, option, shift) {
        case ("t", false, false):
            newTab(); return true
        case ("w", false, false):
            guard tabs.count > 1 else { return nil }
            closeTab(selectedTabID); return true
        case ("n", false, true):
            makeNewFolder(); return true
        case ("s", true, false):
            toggleSplit(); return true
        case ("c", true, false):
            copySelectionPaths(); return true
        case ("r", true, false):
            revealSelectionInFinder(); return true
        case ("y", false, false):
            toggleQuickLook(); return true
        case ("[", false, false):
            guard !isSearching else { return nil }
            activePane.goBack(); return true
        case ("]", false, false):
            guard !isSearching else { return nil }
            activePane.goForward(); return true
        case ("a", false, false):
            guard !isSearching else { return nil }
            activePane.selectAll(); return true
        default:
            break
        }
        switch key {
        case .upArrow? where !option && !shift && !isSearching:
            activePane.goToParent(); return true
        case .downArrow? where !option && !shift:
            openSelection(); return true
        case .backspace?, .delete?, .deleteForward?:
            trashSelection(); return true
        default:
            return nil
        }
    }

    // MARK: Results

    /// ↑/↓ walk both sections, Return opens, Space previews, and → / ← open and close Lookout's "Weaker matches"
    /// fold, as they expand and collapse a disclosure row in Finder.
    private func handleResultsKey(_ key: NSEvent.SpecialKey?, character: String, shift: Bool,
                                  flags: NSEvent.ModifierFlags, event: NSEvent) -> Bool {
        switch key {
        case .downArrow?: moveSearchSelection(by: 1, extending: shift); return true
        case .upArrow?: moveSearchSelection(by: -1, extending: shift); return true
        case .carriageReturn?, .enter?: openSelection(); return true
        case .rightArrow? where flags.isEmpty && isPictureSearch:
            // The selected hit's group's fold.
            guard let group = selectedPictureGroup, !group.weak.isEmpty, !pictureWeakExpanded.contains(group.kind)
            else { return true }
            setPictureWeakExpanded(group.kind, true); return true
        case .leftArrow? where flags.isEmpty && isPictureSearch:
            guard let group = selectedPictureGroup, pictureWeakExpanded.contains(group.kind) else { return true }
            setPictureWeakExpanded(group.kind, false); return true
        case .rightArrow? where flags.isEmpty && !lookoutWeakExpanded && !lookoutResults.weak.isEmpty:
            setLookoutWeakExpanded(true); return true
        case .leftArrow? where flags.isEmpty && lookoutWeakExpanded:
            setLookoutWeakExpanded(false); return true
        default: break
        }
        if character == " ", flags.isEmpty { toggleQuickLook(); return true }
        return typeIntoSearch(event, flags: flags)
    }

    // MARK: Panes

    private func handlePaneKey(_ key: NSEvent.SpecialKey?, character: String, shift: Bool,
                               flags: NSEvent.ModifierFlags, event: NSEvent) -> Bool {
        let tab = selectedTab, pane = tab.activePane
        switch key {
        case .tab?, .backTab?:
            guard tab.isSplit, flags.subtracting(.shift).isEmpty else { return false }
            activatePane(1 - tab.activePaneIndex)
            return true
        case .downArrow?:
            pane.moveSelection(by: tab.viewMode == .icons ? max(1, pane.iconColumns) : 1, extending: shift)
            return true
        case .upArrow?:
            pane.moveSelection(by: tab.viewMode == .icons ? -max(1, pane.iconColumns) : -1, extending: shift)
            return true
        case .leftArrow?:
            switch tab.viewMode {
            case .icons: pane.moveSelection(by: -1, extending: shift); return true
            case .columns: pane.goToParent(); return true
            case .list: return false
            }
        case .rightArrow?:
            switch tab.viewMode {
            case .icons: pane.moveSelection(by: 1, extending: shift); return true
            case .columns:
                if pane.selection.count == 1, let item = pane.selectedItems.first, item.isDirectory {
                    open(item, in: pane)
                }
                return true
            case .list: return false
            }
        case .carriageReturn?, .enter?:
            openSelection()
            return true
        default:
            break
        }
        if character == " ", flags.isEmpty { toggleQuickLook(); return true }
        return typeIntoSearch(event, flags: flags)
    }

    /// Printable typing in the content starts a search in the header field.
    private func typeIntoSearch(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.subtracting([.shift, .option]).isEmpty, event.specialKey == nil,
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              characters != " " || isSearching
        else { return false }
        query += characters
        shell?.focusSearchField()
        return true
    }
}
