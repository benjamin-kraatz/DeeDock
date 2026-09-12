import AppKit
import Observation

/// Owns the shared Shelf: one staging bin visible on every display's dock.
///
/// Items are references; the Shelf never copies, moves, or deletes a file. Opt-in Compost
/// aging uses one deadline plus wake notifications, independently of panel visibility.
@MainActor @Observable
final class ShelfController {
    private(set) var items: [ShelfItem] = []
    private(set) var sort: ShelfSort = .dateAdded
    private(set) var presentation: ShelfPresentation = .list
    private(set) var compost: [ShelfCompostEntry] = []
    private(set) var compostPolicy: ShelfCompostPolicy = .off
    private(set) var compostFailure: String?
    private(set) var item: ShelfDockItem
    /// Set when stored bytes could not be read. Further writes are refused until `reset()`.
    private(set) var requiresReset = false
    private(set) var loadFailure: String?
    @ObservationIgnored var didChange: (() -> Void)?

    @ObservationIgnored private let compostScheduler = ShelfCompostScheduler()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let repository: ShelfRepository
    @ObservationIgnored private let bookmark: (URL) throws -> Data

    init(repository: ShelfRepository = ShelfRepository(),
         now: @escaping () -> Date = Date.init,
         bookmark: @escaping (URL) throws -> Data = {
             try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                 includingResourceValuesForKeys: nil, relativeTo: nil)
         }) {
        self.now = now
        self.repository = repository
        self.bookmark = bookmark
        item = ShelfDockItem(count: 0, icon: Self.icon(empty: true))
    }

    func start() {
        compostScheduler.stop()
        compostFailure = nil
        do {
            let document = try repository.load() ?? ShelfDocument()
            items = document.items
            sort = document.sort
            presentation = document.presentation
            compost = document.compost
            compostPolicy = document.compostPolicy
            requiresReset = false
            loadFailure = nil
        } catch {
            // The stored bytes stay untouched so the user's items can still be recovered.
            items = []
            compost = []
            compostPolicy = .off
            requiresReset = true
            loadFailure = error.localizedDescription
        }
        refreshItem()
        if !requiresReset {
            compostScheduler.start { [weak self] in self?.refreshCompost() }
            refreshCompost()
        }
    }

    /// Discards unreadable storage at the user's explicit request and re-enables writes.
    func reset() throws {
        try repository.save(ShelfDocument())
        items = []
        compost = []
        compostPolicy = .off
        compostFailure = nil
        sort = .dateAdded
        presentation = .list
        compostScheduler.schedule(nil)
        requiresReset = false
        loadFailure = nil
        refreshItem()
        compostScheduler.start { [weak self] in self?.refreshCompost() }
        didChange?()
    }

    var isEmpty: Bool { items.isEmpty }
    /// The staged items in the order the panel shows them.
    var ordered: [ShelfItem] { document(items).ordered() }

    /// View choices persist like the items themselves, so the panel opens the way it was left.
    func setSort(_ value: ShelfSort) throws {
        guard value != sort else { return }
        let previous = sort
        sort = value
        do { try commit(items) } catch { sort = previous; throw error }
    }

    func setPresentation(_ value: ShelfPresentation) throws {
        guard value != presentation else { return }
        let previous = presentation
        presentation = value
        do { try commit(items) } catch { presentation = previous; throw error }
    }

    // MARK: - Editing

    /// Stages a user-supplied batch, newest first. Returns the number of items that did not fit.
    /// Already-staged locations are skipped rather than duplicated.
    @discardableResult
    func add(_ urls: [URL]) throws -> Int {
        guard !requiresReset else { throw CocoaError(.coderReadCorrupt) }
        let staged = Set(items.map(\.url.standardizedFileURL))
        var accepted: [ShelfItem] = []
        var rejected = 0
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !staged.contains(standardized),
                  !accepted.contains(where: { $0.url == standardized }) else { continue }
            guard items.count + accepted.count < ShelfDocument.capacity else {
                rejected += 1
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
                rejected += 1
                continue
            }
            if let archived = compost.first(where: { $0.item.url.standardizedFileURL == standardized }) {
                var restored = archived.item
                restored.addedAt = now()
                restored.bookmarkData = try bookmark(standardized)
                accepted.append(restored)
                continue
            }
            accepted.append(ShelfItem(url: standardized,
                                      name: FileManager.default.displayName(atPath: standardized.path),
                                      bookmarkData: try bookmark(standardized),
                                      addedAt: now(),
                                      isDirectory: isDirectory.boolValue))
        }
        guard !accepted.isEmpty else {
            if rejected > 0 { return rejected }
            return 0
        }
        var next = document(accepted.reversed() + items)
        let restoredIDs = Set(accepted.map(\.id))
        next.compost.removeAll { restoredIDs.contains($0.id) }
        try commit(next)
        return rejected
    }

    func remove(ids: Set<UUID>) throws {
        guard items.contains(where: { ids.contains($0.id) }) else { return }
        try commit(items.filter { !ids.contains($0.id) })
    }

    func clear() throws {
        guard !items.isEmpty else { return }
        try commit([])
    }

    // MARK: - Access

    func item(with id: UUID) -> ShelfItem? { items.first { $0.id == id } }

    /// Resolves one staged item, refreshing a stale bookmark in place when it can.
    func resolve(_ id: UUID) -> ShelfResourceAccess? {
        guard let staged = item(with: id),
              !QuarantineStore.shared.contains(id.uuidString, url: staged.url),
              !QuarantineStore.shared.unreadable else { return nil }
        let access = ShelfResourceAccess(staged)
        guard access.isAvailable, !QuarantineStore.shared.blocks(access.url) else { return nil }
        if access.bookmarkIsStale, let refreshed = try? bookmark(access.url),
           let index = items.firstIndex(where: { $0.id == id }) {
            var updated = items
            updated[index].bookmarkData = refreshed
            // A refresh that cannot be saved still leaves this session's access usable.
            try? commit(updated, notify: false)
        }
        return access
    }

    /// Resolves every staged item, dropping the ones that no longer exist.
    func resolveAll() -> [ShelfResourceAccess] {
        items.compactMap { resolve($0.id) }
    }

    func isAvailable(_ item: ShelfItem) -> Bool {
        ShelfResourceAccess(item, startAccess: { _ in false }, stopAccess: { _ in }).isAvailable
    }

    /// Applies a visible rule and its first aging pass in one persisted update.
    func setCompostPolicy(_ policy: ShelfCompostPolicy) throws {
        var next = document(items)
        next.compostPolicy = policy
        next.compostAgedItems(at: now())
        try commit(next)
    }

    /// Restores even unavailable files as references. A full Shelf leaves the archive untouched.
    func restoreFromCompost(_ id: UUID) throws {
        guard let entry = compost.first(where: { $0.id == id }) else { return }
        guard items.count < ShelfDocument.capacity else { throw ShelfCompostError.shelfFull }
        guard !items.contains(where: { $0.url.standardizedFileURL == entry.item.url.standardizedFileURL }) else {
            throw ShelfCompostError.alreadyStaged
        }
        var restored = entry.item
        restored.addedAt = now()
        var next = document([restored] + items)
        next.compost.removeAll { $0.id == id }
        try commit(next)
    }

    /// Forgets one archived reference only after the UI's explicit confirmation. Files stay put.
    func forgetCompost(_ id: UUID) throws {
        var next = document(items)
        next.compost.removeAll { $0.id == id }
        guard next.compost != compost else { return }
        try commit(next)
        refreshCompost()
    }

    /// Reconciles elapsed time at startup, wake, panel opening, and the next aging deadline.
    func refreshCompost() {
        guard !requiresReset else { return }
        var next = document(items)
        next.compostAgedItems(at: now())
        do {
            if next.items != items { try commit(next) }
            else { compostScheduler.schedule(next.nextCompostDate) }
        } catch {
            compostFailure = String(localized: .errorSaveShelf(details: error.localizedDescription))
            // Retry on wake, opening, or an explicit action, without a tight failure loop.
            compostScheduler.schedule(nil)
            didChange?()
        }
    }

    func stop() { compostScheduler.stop(); didChange = nil }

    // MARK: - Private

    private func document(_ items: [ShelfItem]) -> ShelfDocument {
        ShelfDocument(items: items, sort: sort, presentation: presentation,
                      compost: compost, compostPolicy: compostPolicy)
    }

    private func commit(_ next: [ShelfItem], notify: Bool = true) throws {
        try commit(document(next), notify: notify)
    }

    /// Publish only after the entire active/archive document has been saved successfully.
    private func commit(_ next: ShelfDocument, notify: Bool = true) throws {
        guard !requiresReset else { throw CocoaError(.coderReadCorrupt) }
        try repository.save(next)
        items = next.items
        sort = next.sort
        presentation = next.presentation
        compost = next.compost
        compostPolicy = next.compostPolicy
        compostFailure = nil
        compostScheduler.schedule(next.nextCompostDate)
        refreshItem()
        if notify { didChange?() }
    }

    private func refreshItem() {
        item = ShelfDockItem(count: items.count, icon: Self.icon(empty: items.isEmpty))
    }

    /// The tile artwork. SF Symbols read heavier than real app icons at the same box size, so the
    /// glyph is drawn inset into a full-size canvas rather than scaled to fill it.
    private static func icon(empty: Bool) -> NSImage {
        let dimension: CGFloat = 128
        let symbol = empty ? "rectangle.stack" : "rectangle.stack.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 74, weight: .regular)
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: dimension, height: dimension))
        }
        let canvas = NSImage(size: NSSize(width: dimension, height: dimension), flipped: false) { _ in
            let size = glyph.size
            glyph.draw(in: NSRect(x: (dimension - size.width) / 2,
                                  y: (dimension - size.height) / 2,
                                  width: size.width, height: size.height))
            return true
        }
        canvas.isTemplate = true
        return canvas
    }
}
