import AppKit
import Observation

/// App-lifetime owner for the user's shared capsule collection.
@MainActor @Observable
final class SessionCapsuleController {
    private(set) var capsules: [SessionCapsule] = []
    private(set) var item: CapsuleDockItem
    private(set) var dockItems: [SessionCapsuleDockItem] = []
    private(set) var requiresReset = false
    private(set) var loadFailure: String?
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private let repository: SessionCapsuleRepository

    init(repository: SessionCapsuleRepository = SessionCapsuleRepository()) {
        self.repository = repository
        item = CapsuleDockItem(count: 0, icon: SessionCapsuleController.icon())
    }

    func start() {
        do {
            capsules = (try repository.load() ?? SessionCapsuleDocument()).capsules
                .sorted { $0.createdAt > $1.createdAt }
            requiresReset = false
            loadFailure = nil
        } catch {
            capsules = []
            requiresReset = true
            loadFailure = error.localizedDescription
        }
        refreshItem()
    }

    func save(_ capsule: SessionCapsule) throws {
        guard !requiresReset else { throw CocoaError(.coderReadCorrupt) }
        var next = capsules.filter { $0.id != capsule.id }
        next.insert(capsule, at: 0)
        if next.count > SessionCapsuleDocument.capacity { next.removeLast(next.count - SessionCapsuleDocument.capacity) }
        try commit(next)
    }

    func delete(_ id: UUID) throws {
        guard capsules.contains(where: { $0.id == id }) else { return }
        try commit(capsules.filter { $0.id != id })
    }

    func reset() throws {
        try repository.save(SessionCapsuleDocument())
        capsules = []
        requiresReset = false
        loadFailure = nil
        refreshItem()
        didChange?()
    }

    func stop() { didChange = nil }

    private func commit(_ next: [SessionCapsule]) throws {
        let document = SessionCapsuleDocument(capsules: next)
        try repository.save(document)
        capsules = next
        refreshItem()
        didChange?()
    }

    private func refreshItem() {
        item = CapsuleDockItem(count: capsules.count, icon: Self.icon())
        dockItems = capsules.map {
            SessionCapsuleDockItem(capsuleID: $0.id, title: $0.title, icon: Self.icon(),
                                   applicationIcons: SessionCapsuleApplicationIcons.icons(for: $0.windows))
        }
    }

    /// Rasterized capsule mark, kept for drag previews and any other `NSImage` consumer.
    ///
    /// The Dock tiles draw `CapsuleGlyph` directly; rendering here once keeps a dragged tile looking
    /// like the tile it came from without re-rasterizing on every collection change.
    private static let rasterizedMark: NSImage = CapsuleGlyph.image()

    private static func icon() -> NSImage { rasterizedMark }
}
