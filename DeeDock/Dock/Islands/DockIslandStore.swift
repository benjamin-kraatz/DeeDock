import Foundation
import Observation

/// Saves each display's island edits and remembers the tiles its dock last showed.
///
/// Automatic sections are not written down. The first rename, move, or new island stores a
/// document for that display. Reset deletes it, and the dock generates sections again.
@MainActor @Observable
final class DockIslandStore {
    private(set) var documents: [String: DockIslandDocument] = [:]
    private(set) var snapshots: [String: [DockIslandSlotSnapshot]] = [:]
    /// Fired after a person edits islands. Refreshing the tile list does not call it.
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "dock.island-layout.v1"

    private struct Document: Codable {
        var version = 1
        var displays: [String: DockIslandDocument]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let document = try? JSONDecoder().decode(Document.self, from: data), document.version == 1 {
            documents = document.displays
        }
    }

    func document(for displayID: String) -> DockIslandDocument {
        documents[displayID] ?? .automatic
    }

    func isCustomized(_ displayID: String) -> Bool {
        document(for: displayID).customized
    }

    /// Records the tiles on one dock. Names come from macOS and are not translated.
    func remember(displayID: String, slots: [DockRenderSlot]) {
        let next = slots.compactMap(DockIslandArrangement.snapshot(of:))
        guard snapshots[displayID] != next else { return }
        snapshots[displayID] = next
    }

    func editorIslands(for displayID: String) -> [DockIslandEditorIsland] {
        DockIslandArrangement.editorIslands(snapshots: snapshots[displayID] ?? [], document: document(for: displayID))
    }

    func arrangedSlots(_ slots: [DockRenderSlot], displayID: String) -> [DockRenderSlot] {
        DockIslandArrangement.arrangedSlots(slots, document: document(for: displayID))
    }

    func breaks(in slots: [DockRenderSlot], displayID: String) -> [DockIslandBreak] {
        DockIslandArrangement.breaks(in: slots, document: document(for: displayID))
    }

    func resolvedTitle(_ title: DockIslandTitle) -> String {
        switch title {
        case .role(let role): String(localized: role.title)
        case .launcher: String(localized: .launcherTitle)
        case .text(let name):
            name.isEmpty ? String(localized: .islandsNewName) : name
        }
    }

    func rename(displayID: String, islandID: String, to name: String) {
        edit(displayID: displayID) { document, snapshots in
            DockIslandArrangement.renaming(document, islandID: islandID, to: name, snapshots: snapshots)
        }
    }

    func moveIsland(displayID: String, id: String, by distance: Int) {
        edit(displayID: displayID) { document, snapshots in
            DockIslandArrangement.movingIsland(document, id: id, by: distance, snapshots: snapshots)
        }
    }

    func moveMember(displayID: String, memberID: String, to islandID: String) {
        edit(displayID: displayID) { document, snapshots in
            DockIslandArrangement.movingMember(document, memberID: memberID, to: islandID, snapshots: snapshots)
        }
    }

    func addIsland(displayID: String) {
        edit(displayID: displayID) { document, snapshots in
            DockIslandArrangement.addingIsland(document, snapshots: snapshots)
        }
    }

    func deleteIsland(displayID: String, id: String) {
        edit(displayID: displayID) { document, snapshots in
            DockIslandArrangement.deletingIsland(document, id: id, snapshots: snapshots)
        }
    }

    func reset(displayID: String) {
        guard documents[displayID] != nil else { return }
        documents[displayID] = nil
        save()
        didChange?()
    }

    private func edit(displayID: String, change: (DockIslandDocument, [DockIslandSlotSnapshot]) -> DockIslandDocument) {
        let snapshots = snapshots[displayID] ?? []
        let next = change(document(for: displayID), snapshots)
        guard next != document(for: displayID) else { return }
        documents[displayID] = next
        save()
        didChange?()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Document(displays: documents)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
