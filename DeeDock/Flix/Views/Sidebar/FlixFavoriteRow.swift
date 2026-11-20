import SwiftUI
import UniformTypeIdentifiers

/// A Favorite in the sidebar, and a drop target for rows dragged out of the list.
struct FlixFavoriteRow: View {
    let favorite: FlixFavorite
    let state: FlixPanelState
    let count: Int?
    @State private var targeted = false

    var body: some View {
        FlixSidebarRow(title: Text(verbatim: favorite.name), glyph: .image(icon), count: count,
                       selected: state.filter == .favorite(favorite.id), targeted: targeted) {
            state.activate(favorite)
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { targeted }, set: { targeted = $0 && accepts })) { _ in
            guard accepts, let ids = state.drag?.itemIDs else { return false }
            state.drop(ids, on: favorite)
            return true
        }
        .contextMenu {
            Button { FlixFileActions.reveal([FlixItem(path: favorite.path, name: favorite.name, kind: .folder,
                                                      activity: .opened, date: .now)]) } label: { Text(.flixMenuShowInFinder) }
            Button(role: .destructive) {
                if state.filter == .favorite(favorite.id) { state.filter = .all }
                state.history.removeFavorite(favorite.id)
            } label: { Text(.flixFavoriteRemove) }
        }
        .accessibilityHint(Text(favorite.kind == .folder ? .flixFavoriteFolderHint : .flixFavoriteAppHint))
    }

    /// Only Flix's own drags land here; a folder or app favorite takes them.
    private var accepts: Bool { state.drag != nil && favorite.kind != .file }

    private var icon: NSImage {
        let item = FlixItem(path: favorite.path, name: favorite.name,
                            kind: favorite.kind == .folder ? .folder : favorite.kind == .app ? .app : .other,
                            activity: .opened, date: .distantPast,
                            bundleIdentifier: favorite.kind == .app ? Bundle(path: favorite.path)?.bundleIdentifier : nil)
        return FlixIconProvider.icon(for: item, policy: state.readPolicy)
    }
}
