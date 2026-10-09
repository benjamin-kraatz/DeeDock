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

    /// Shared selection, drag, drop, and menu behavior for list rows, tiles, and column items.
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

    /// A sidebar place or drive: a click shows it in the active pane; drops land in its folder.
    static func sidebar(_ location: HubFilesLocation, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseUp = { _ in model.show(location) }
        if let folder = location.folderURL {
            interaction.dropDestination = { folder }
            interaction.dropHighlight = .sidebar(folder)
            interaction.springLoad = { model.show(location) }
        }
        interaction.hoverChanged = hover
        return interaction
    }

    /// A browser tab: a click selects it; drops land in its active pane's folder; resting on it
    /// during a drag switches to it.
    static func tab(_ tab: HubFilesBrowserTab, model: HubFilesModel, hover: @escaping (Bool) -> Void) -> HubFilesInteraction {
        var interaction = HubFilesInteraction()
        interaction.mouseDown = { _ in model.selectTab(tab.id) }
        interaction.dropDestination = { model.dropFolder(for: tab) }
        interaction.dropHighlight = .tab(tab.id)
        interaction.springLoad = { model.selectTab(tab.id) }
        interaction.hoverChanged = hover
        return interaction
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
