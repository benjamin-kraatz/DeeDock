import AppKit
import Observation
import SwiftUI

/// What the Favorites list shows beyond the stored entries: drag slots and targets, the row being
/// reordered, arrival glows and pulses, the Undo offer, and the problem popover.
///
/// Owned by `HubFilesModel`; `store` holds the list itself. All drag entry points come from
/// `HubFilesInteractionView` on the main actor. Overlay windows (drag label, lifted row, poof,
/// flight) are created on first use and hidden, never closed, so they can be reused.
@MainActor @Observable
final class HubFilesSidebarModel {
    /// The end slot that appears under Favorites while a drag carrying folders is over the Hub.
    struct EndSlot: Equatable {
        var folderCount: Int
        /// The pointer is over it: it previews the folder that will be added.
        var isTargeted: Bool
    }

    /// What an insertion slot (or a targeted end slot) previews.
    struct SlotPreview: Equatable {
        var symbolName: String
        var title: String
    }

    /// A one-shot highlight on a row. `token` changes for every new flash so the row replays it.
    struct Flash: Equatable {
        enum Kind: Equatable {
            /// The row was just added or restored: an accent glow with a light sweep.
            case arrival
            /// The folder was already there: a short pulse.
            case pulse
        }
        var kind: Kind
        var token: Int
    }

    /// One removal command (one row, or every row a menu command removed) that can still be
    /// undone from the toast or with ⌘Z.
    struct UndoOffer: Equatable {
        /// In the order they were removed: highest index first, so each index is the row's
        /// original position. Undo restores them in reverse.
        let removals: [HubFilesSidebarStore.Removal]
        /// The row's name when one row was removed; nil for several.
        let title: String?
        let token: Int
    }

    let store: HubFilesSidebarStore
    /// The Files model, for drop operations, navigation, and the shell. Set by its owner.
    @ObservationIgnored weak var files: HubFilesModel?

    // MARK: Drawn state

    /// Where an insertion slot is open, as an index into `store.entries`.
    var slotIndex: Int?
    /// The open slot's height: a row's, or the lifted row's while reordering.
    var slotHeight: CGFloat = HubFilesMetrics.rowHeight
    var slotPreview: SlotPreview?
    var endSlot: EndSlot?
    /// The row a file drop would land in.
    var intoTarget: HubFilesSidebarEntryID?
    /// The row lifted out of the list while it is dragged.
    var liftedID: HubFilesSidebarEntryID?
    private(set) var flashes: [HubFilesSidebarEntryID: Flash] = [:]
    /// Rows added from a menu that stay invisible until the flying icon lands on them.
    private(set) var awaitingFlight: Set<HubFilesSidebarEntryID> = []
    private(set) var undo: UndoOffer?
    /// The missing or disconnected folder whose explanation popover is showing.
    var problem: HubFilesSidebarEntryID?

    // MARK: Plumbing

    @ObservationIgnored var rowViews: [HubFilesSidebarEntryID: HubFilesWeakView] = [:]
    @ObservationIgnored weak var favoritesView: NSView?
    @ObservationIgnored weak var sidebarView: NSView?
    @ObservationIgnored weak var slotView: NSView?
    @ObservationIgnored weak var endSlotView: NSView?
    @ObservationIgnored var itemDrag: HubFilesSidebarItemDrag?
    @ObservationIgnored var reorder: HubFilesSidebarReorder?
    @ObservationIgnored lazy var labelWindow = HubFilesOverlayWindow()
    @ObservationIgnored lazy var liftWindow = HubFilesOverlayWindow()
    /// The reorder whose lifted row is still gliding into its slot, and how to land it now.
    @ObservationIgnored var pendingSettle: (serial: Int, finish: @MainActor () -> Void)?
    @ObservationIgnored var settleSerial = 0
    /// Changes when a reorder is aborted, so a tracking loop still running for it stops.
    @ObservationIgnored private(set) var reorderSession = 0
    /// Menu-add flights in progress, owned so a hidden tab can stop them.
    @ObservationIgnored var flightTasks: [Task<Void, Never>] = []
    @ObservationIgnored var flightWindows: [HubFilesOverlayWindow] = []
    @ObservationIgnored private var flashSerial = 0
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    init(store: HubFilesSidebarStore) {
        self.store = store
    }

    isolated deinit {
        undoTask?.cancel()
        flightTasks.forEach { $0.cancel() }
        flightWindows.forEach { $0.hide() }
    }

    // MARK: Row state

    func flash(for id: HubFilesSidebarEntryID) -> Flash? { flashes[id] }

    func isAwaitingFlight(_ id: HubFilesSidebarEntryID) -> Bool { awaitingFlight.contains(id) }

    /// Plays the arrival glow or the pulse on rows. Reduce Motion keeps the pulse (a plain fill
    /// change) but skips the glow's sweep; the row view decides.
    func flash(_ ids: [HubFilesSidebarEntryID], _ kind: Flash.Kind) {
        for id in ids {
            flashSerial += 1
            let token = flashSerial
            flashes[id] = Flash(kind: kind, token: token)
            // Forget it once played, so a row rebuilt later (the tab reopening) doesn't replay it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                if self?.flashes[id]?.token == token { self?.flashes[id] = nil }
            }
        }
    }

    /// Subtitle that tells two rows with the same name apart: the enclosing folder's name.
    func duplicateSubtitle(for folder: HubFilesSidebarFolder) -> String? {
        let name = store.title(for: .folder(folder))
        let clashes = store.entries.contains { other in
            other.id != .folder(folder.id) && store.title(for: other).localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard clashes else { return nil }
        let parent = store.resolutions[folder.id]?.parentName
        return parent?.isEmpty == false ? parent : HubFilesPath.parent(of: folder.url)?.lastPathComponent
    }

    // MARK: Opening rows

    /// A click on a Favorites row: shows its folder, or explains why it can't.
    func open(_ id: HubFilesSidebarEntryID) {
        guard let entry = store.entry(id), let files else { return }
        if let location = store.location(for: entry) {
            files.show(location)
        } else {
            problem = id
        }
    }

    func openInNewTab(_ id: HubFilesSidebarEntryID) {
        guard let entry = store.entry(id), let location = store.location(for: entry), let files else { return }
        files.newTab()
        files.show(location)
    }

    // MARK: Adding

    /// Adds folders at the end of Favorites from a context menu or ⌃⌘T. `urls` are folders
    /// (callers pass directory items that aren't packages).
    ///
    /// Folders already in the sidebar pulse instead. With a `flightOrigin` (the screen point the
    /// menu opened at) each new row stays hidden while a copy of its icon arcs there from the item.
    func addFromCommand(_ urls: [URL], method: AnalyticsHubSidebarMethod, flightOrigin: CGPoint?) {
        let existing = urls.compactMap { store.entryID(for: $0) }
        let fresh = urls.filter { store.entryID(for: $0) == nil }
        flash(existing, .pulse)
        guard !fresh.isEmpty else { return }
        let added = HubFilesMotion.withLayoutAnimation { store.insert(fresh, at: store.entries.count).added }
        Analytics.track(.hubFilesSidebarEdited(.add, method: method, itemCount: added.count))
        guard let flightOrigin, !HubFilesMotion.reduceMotion else {
            flash(added, .arrival)
            return
        }
        awaitingFlight.formUnion(added)
        flightTasks.append(Task { [weak self] in
            // The new rows get views and frames on SwiftUI's next update; wait a few frames for them.
            for _ in 0..<6 {
                guard let self else { return }
                if added.allSatisfy({ self.rowViews[$0]?.view?.window != nil }) { break }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            self?.launchFlights(for: added, urls: fresh, from: flightOrigin)
        })
    }

    /// Drops a reorder in progress without committing it: the row goes back where it was, with no
    /// animation, and the tracking loop for it ends. Called when the Files tab hides, so a release
    /// after the Hub closed can't move or remove a row.
    func abortReorder() {
        reorderSession += 1
        finishPendingSettle()
        guard reorder != nil else { return }
        reorder = nil
        NSCursor.arrow.set()
        files?.shell?.endHold(.drag)
        liftWindow.hide()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            liftedID = nil
            slotIndex = nil
            slotPreview = nil
        }
    }

    /// Stops every flight and shows the rows they were headed for. Called when the Files tab hides,
    /// so no icon keeps flying over another tab or the desktop.
    func cancelFlights() {
        flightTasks.forEach { $0.cancel() }
        flightTasks.removeAll()
        flightWindows.forEach { $0.hide() }
        flightWindows.removeAll()
        awaitingFlight.removeAll()
    }

    /// Ends a flight: shows the row it landed on and plays the arrival glow.
    func flightLanded(on id: HubFilesSidebarEntryID) {
        awaitingFlight.remove(id)
        flash([id], .arrival)
    }

    // MARK: Removing and Undo

    /// Removes rows as one command and offers Undo for all of them for five seconds.
    func remove(_ ids: [HubFilesSidebarEntryID], method: AnalyticsHubSidebarMethod, animated: Bool = true) {
        let ordered = ids.compactMap { id in store.index(of: id).map { (id, $0) } }
            .sorted { $0.1 > $1.1 }
        guard !ordered.isEmpty else { return }
        let title = ordered.count == 1 ? store.entry(ordered[0].0).map(store.title(for:)) : nil
        // Highest index first, so removing one row doesn't shift the rows still to go, and each
        // recorded index is that row's original position.
        let removeAll = { ordered.compactMap { self.store.remove($0.0) } }
        let removals = animated ? HubFilesMotion.withLayoutAnimation(removeAll) : removeAll()
        if let problem, ids.contains(problem) { self.problem = nil }
        Analytics.track(.hubFilesSidebarEdited(.remove, method: method, itemCount: removals.count))
        offerUndo(removals, title: title)
    }

    /// Puts the last removed rows back where they were. Returns false when there is nothing to undo.
    @discardableResult
    func undoRemoval() -> Bool {
        guard let undo else { return false }
        dismissUndo()
        let restored = HubFilesMotion.withLayoutAnimation {
            undo.removals.reversed().compactMap { store.restore($0) }
        }
        flash(restored, .arrival)
        Analytics.track(.hubFilesSidebarEdited(.undo, method: .toast, itemCount: restored.count))
        return true
    }

    func dismissUndo() {
        undoTask?.cancel()
        undoTask = nil
        undo = nil
    }

    private func offerUndo(_ removals: [HubFilesSidebarStore.Removal], title: String?) {
        flashSerial += 1
        undo = UndoOffer(removals: removals, title: title, token: flashSerial)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undo = nil
        }
    }

    // MARK: Restoring places

    /// Brings back every removed built-in place, each in its default position.
    func restoreDefaultPlaces(method: AnalyticsHubSidebarMethod) {
        let restored = HubFilesMotion.withLayoutAnimation { store.restoreDefaultPlaces() }
        guard !restored.isEmpty else { return }
        flash(restored.map(HubFilesSidebarEntryID.place), .arrival)
        Analytics.track(.hubFilesSidebarEdited(.restore, method: method, itemCount: restored.count))
    }

    // MARK: Accessibility

    /// Moves a row one step up (`-1`) or down (`1`) and announces its new position.
    func move(_ id: HubFilesSidebarEntryID, by step: Int) {
        guard let index = store.index(of: id) else { return }
        let target = step < 0 ? index - 1 : index + 2
        guard target >= 0, target <= store.entries.count else { return }
        HubFilesMotion.withLayoutAnimation { store.move(id, to: target) }
        Analytics.track(.hubFilesSidebarEdited(.reorder, method: .accessibility, itemCount: 1))
        if let position = store.index(of: id) {
            AccessibilityNotification.Announcement(
                String(localized: .hubFilesSidebarPositionAnnouncement(position + 1, store.entries.count))).post()
        }
    }

    // MARK: Folders

    /// The folders among `urls` that can be sidebar rows: real folders, not packages, app bundles,
    /// or volume roots. Reads resource values, so callers cache the result per drag.
    nonisolated static func addableFolders(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            guard !HubFilesPath.isVolumeRoot(url),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
            return values.isDirectory == true && values.isPackage != true
        }
        .map(HubFilesPath.normalized)
    }
}

/// A weak reference to a view that registered its frame with the sidebar.
struct HubFilesWeakView {
    weak var view: NSView?
}

extension NSView {
    /// The view's bounds in AppKit screen coordinates, or nil when it has no window.
    var screenFrame: CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}

extension HubFilesMotion {
    /// Runs `body` inside the Hub's layout spring, or without animation under Reduce Motion.
    @discardableResult
    static func withLayoutAnimation<Result>(_ body: () throws -> Result) rethrows -> Result {
        try withAnimation(layout, body)
    }
}
