import AppKit

/// Builds the native interaction for each kind of Files region from the model.
@MainActor
enum HubFilesInteractions {
    /// A row or tile in list or icon view.
    static func item(_ item: HubFileItem, pane: HubFilesPane, paneIndex: Int, model: HubFilesModel,
                     hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = selectable(item, pane: pane, paneIndex: paneIndex, model: model)
        interaction.doubleClick = { model.open(item, in: pane) }
        interaction.hoverChanged = hover
        return interaction
    }

    /// An item in a column-view column. A click on a folder opens it as the next column; a click on
    /// a file shows its folder as the last column and selects it, as in Finder.
    static func columnItem(_ item: HubFileItem, column: URL, pane: HubFilesPane, paneIndex: Int,
                           model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = selectable(item, pane: pane, paneIndex: paneIndex, model: model)
        interaction.mouseDown = { event in
            model.activatePane(paneIndex)
            if item.isDirectory {
                pane.navigate(to: .folder(normalizing: item.url))
            } else {
                if !HubFilesPath.same(pane.folderURL ?? column, column) { pane.navigate(to: .folder(normalizing: column)) }
                pane.selectWhenListed([item.url])
            }
        }
        interaction.mouseUp = nil
        interaction.dragURLs = { [item.url] }
        interaction.doubleClick = { if !item.isDirectory { model.open(item, in: pane) } }
        interaction.hoverChanged = hover
        return interaction
    }

    /// Shared selection, drag, drop, and menu behavior for list rows, tiles, and column items. A
    /// middle click on a folder shows it in a browser tab (Shift: in a background tab) and leaves
    /// the selection alone.
    private static func selectable(_ item: HubFileItem, pane: HubFilesPane, paneIndex: Int,
                                   model: HubFilesModel) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { event in
            model.activatePane(paneIndex)
            let flags = event.modifierFlags
            if flags.contains(.command) {
                pane.click(item.url, mode: .toggle)
            } else if flags.contains(.shift) {
                pane.click(item.url, mode: .extend)
            } else if !pane.selection.contains(item.url) {
                pane.click(item.url, mode: .replace)
            }
        }
        // A plain click on an already selected item narrows to it only on mouse-up, so dragging a
        // multiple selection by one of its items keeps the whole selection.
        interaction.mouseUp = { event in
            guard event.modifierFlags.intersection([.command, .shift]).isEmpty, pane.selection.count > 1 else { return }
            pane.click(item.url, mode: .replace)
        }
        interaction.dragURLs = {
            pane.selection.contains(item.url) ? pane.selectedItems.map(\.url) : [item.url]
        }
        interaction.dragHold = dragHold(model)
        if item.isDirectory {
            interaction.dropDestination = { item.url }
            interaction.dropHighlight = .item(item.url)
            interaction.springLoad = {
                model.activatePane(paneIndex)
                pane.navigate(to: .folder(normalizing: item.url))
            }
            if !item.isPackage {
                interaction.middleClick = {
                    model.showInTab(.folder(normalizing: item.url), inBackground: opensInBackground($0))
                }
            }
        } else {
            interaction.dropDestination = { pane.folderURL }
            interaction.dropHighlight = .pane(pane.id)
        }
        interaction.menu = {
            model.activatePane(paneIndex)
            if !pane.selection.contains(item.url) { pane.click(item.url, mode: .replace) }
            return HubFilesContextMenu.items(model: model)
        }
        return interaction
    }

    /// The empty area of a pane: clears the selection and accepts drops into the pane's folder.
    static func paneBackground(_ pane: HubFilesPane, paneIndex: Int, model: HubFilesModel) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { _ in
            model.activatePane(paneIndex)
            pane.clearSelection()
        }
        interaction.dropDestination = { pane.folderURL }
        interaction.dropHighlight = .pane(pane.id)
        interaction.menu = {
            model.activatePane(paneIndex)
            pane.clearSelection()
            return HubFilesContextMenu.background(model: model, pane: pane)
        }
        return interaction
    }

    /// One column of the column view: drops land in that column's folder.
    static func columnBackground(_ folder: URL, pane: HubFilesPane, paneIndex: Int, model: HubFilesModel) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { _ in
            model.activatePane(paneIndex)
            if !HubFilesPath.same(pane.folderURL ?? folder, folder) { pane.navigate(to: .folder(normalizing: folder)) }
            pane.clearSelection()
        }
        interaction.dropDestination = { folder }
        interaction.dropHighlight = .column(folder)
        return interaction
    }

    /// A search result row.
    static func searchResult(_ item: HubFileItem, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { event in
            let flags = event.modifierFlags
            if flags.contains(.command) {
                model.clickSearchResult(item.url, mode: .toggle)
            } else if flags.contains(.shift) {
                model.clickSearchResult(item.url, mode: .extend)
            } else if !model.searchSelection.contains(item.url) {
                model.clickSearchResult(item.url, mode: .replace)
            }
        }
        interaction.mouseUp = { event in
            guard event.modifierFlags.intersection([.command, .shift]).isEmpty, model.searchSelection.count > 1 else { return }
            model.clickSearchResult(item.url, mode: .replace)
        }
        interaction.doubleClick = { model.openSearchResult(item) }
        interaction.isSearchResult = true
        interaction.dragURLs = {
            model.searchSelection.contains(item.url) ? model.actionableItems.map(\.url) : [item.url]
        }
        interaction.dragHold = dragHold(model)
        if item.isDirectory {
            interaction.dropDestination = { item.url }
            interaction.dropHighlight = .item(item.url)
        }
        interaction.menu = {
            if !model.searchSelection.contains(item.url) { model.clickSearchResult(item.url, mode: .replace) }
            return HubFilesContextMenu.items(model: model)
        }
        interaction.hoverChanged = hover
        return interaction
    }

    /// A Lookout result row: a click selects the hit alone (Lookout hits don't extend a selection), a double click
    /// opens it, it drags out as its file, and a folder hit accepts drops like a folder name result.
    static func lookoutResult(_ hit: LookoutHit, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        let url = hit.fileItem.url
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { _ in model.clickLookoutResult(hit) }
        interaction.doubleClick = { model.openLookoutResult(hit) }
        interaction.isSearchResult = true
        interaction.dragURLs = { [url] }
        interaction.dragHold = dragHold(model)
        if hit.isFolder {
            interaction.dropDestination = { url }
            interaction.dropHighlight = .item(url)
        }
        interaction.menu = {
            if model.lookoutSelection != hit.path { model.clickLookoutResult(hit) }
            return HubFilesContextMenu.items(model: model)
        }
        interaction.hoverChanged = hover
        return interaction
    }

    /// A sidebar place or drive: a click shows it in the active pane and a middle click in a
    /// browser tab; drops land in its folder.
    static func sidebar(_ location: HubFilesLocation, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseUp = { _ in model.show(location) }
        interaction.middleClick = { model.showInTab(location, inBackground: opensInBackground($0)) }
        if let folder = location.folderURL {
            interaction.dropDestination = { folder }
            interaction.dropHighlight = .sidebar(folder)
            interaction.springLoad = { model.show(location) }
        }
        interaction.hoverChanged = hover
        return interaction
    }

    /// A breadcrumb segment: a click shows its folder in the pane and a middle click in a browser
    /// tab; drops land in that folder, and resting on an ancestor segment during a drag opens it,
    /// like Finder's path bar.
    ///
    /// The current folder's segment takes drops but does not spring-load, since the pane is
    /// already there. Recents is neither a drop target nor spring-loaded.
    static func crumb(_ location: HubFilesLocation, isCurrent: Bool, pane: HubFilesPane, paneIndex: Int,
                      model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseUp = { _ in
            model.activatePane(paneIndex)
            pane.navigate(to: location)
        }
        interaction.middleClick = { model.showInTab(location, inBackground: opensInBackground($0)) }
        if let folder = location.folderURL {
            interaction.dropDestination = { folder }
            interaction.dropHighlight = .crumb(pane: pane.id, folder: folder)
            if !isCurrent {
                interaction.springLoad = {
                    model.activatePane(paneIndex)
                    pane.navigate(to: location)
                }
            }
        }
        interaction.hoverChanged = hover
        return interaction
    }

    /// A Favorites row: a click opens it, a middle click opens it in a browser tab, a drag moves it
    /// or (past the sidebar's edge) removes it, and drops route through the sidebar model, which
    /// picks "insert here" or "into this folder".
    static func favorite(_ id: HubFilesSidebarEntryID, model: HubFilesModel,
                         hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = sidebarDropArea(model: model)
        interaction.mouseUp = { _ in model.sidebar.open(id) }
        interaction.middleClick = { model.sidebar.showInTab(id, inBackground: opensInBackground($0)) }
        interaction.sidebarEntry = id
        interaction.springLoad = { model.sidebar.open(id) }
        interaction.menu = { HubFilesContextMenu.favorite(id, model: model) }
        interaction.hoverChanged = hover
        return interaction
    }

    /// Anywhere in the sidebar that isn't a row (gaps, slots, the end slot): drops route through
    /// the sidebar model, so the space between rows inserts too.
    static func sidebarDropArea(model: HubFilesModel) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.routesDropsToSidebar = true
        return interaction
    }

    /// The Favorites header: a drop area with the Restore Default Places menu.
    static func favoritesHeader(model: HubFilesModel) -> HubFilesInteraction {
        var interaction = sidebarDropArea(model: model)
        interaction.menu = { HubFilesContextMenu.favoritesHeader(model: model) }
        return interaction
    }

    /// A browser tab: a click selects it and a middle click closes it; drops land in its active
    /// pane's folder; resting on it during a drag switches to it.
    static func tab(_ tab: HubFilesBrowserTab, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { _ in model.selectTab(tab.id) }
        interaction.middleClick = { _ in model.closeTab(tab.id) }
        interaction.dropDestination = { model.dropFolder(for: tab) }
        interaction.dropHighlight = .tab(tab.id)
        interaction.springLoad = { model.selectTab(tab.id) }
        interaction.hoverChanged = hover
        return interaction
    }

    /// True for Shift-middle-click, which opens a folder in a background tab. A plain middle click
    /// switches to the tab.
    private static func opensInBackground(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift)
    }

    /// Begins and ends `.drag` on the shell that was current when the session began, so the
    /// hold stays balanced even if the tab disappears mid-drag.
    private static func dragHold(_ model: HubFilesModel) -> (Bool) -> Void {
        weak let model = model
        var held: HubShell?
        return { holding in
            if holding {
                held = model?.shell
                held?.beginHold(.drag)
            } else {
                held?.endHold(.drag)
                held = nil
            }
        }
    }
}
