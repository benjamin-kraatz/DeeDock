import SwiftUI
import UniformTypeIdentifiers

/// A Favorite in the sidebar, and a drop target for rows dragged out of the list.
///
/// While a Flix drag is over it the row turns accent with white text. When the drop lands, the row
/// dips and settles once (``FlixMotion/dialog``), standing in for the dragged icons sinking into
/// it: the system owns the drag image, so the row answers instead. No dip with Reduce Motion.
struct FlixFavoriteRow: View {
    let favorite: FlixFavorite
    let state: FlixPanelState
    let count: Int?
    var selectionNamespace: Namespace.ID?
    @State private var targeted = false
    /// Bumped by each accepted drop.
    @State private var received = 0
    /// The folder's or app's own icon, read in the background; the type icon shows until then.
    @State private var loadedIcon: NSImage?

    var body: some View {
        let reduceMotion = state.reduceMotion
        FlixSidebarRow(title: Text(verbatim: favorite.name), glyph: .image(loadedIcon ?? icon), count: count,
                       selected: state.filter == .favorite(favorite.id), targeted: targeted,
                       selectionNamespace: selectionNamespace) {
            state.activate(favorite)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: received) { content, scale in
            content.scaleEffect(reduceMotion ? 1 : scale)
        } keyframes: { _ in
            SpringKeyframe(0.94, duration: 0.12, spring: .snappy)
            SpringKeyframe(1, duration: 0.4, spring: Spring(response: 0.3, dampingRatio: 0.55))
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { targeted }, set: { targeted = $0 && accepts })) { _ in
            guard accepts, let ids = state.drag?.itemIDs else { return false }
            state.drop(ids, on: favorite)
            received += 1
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
        .help(Text(verbatim: favorite.name))
        .task(id: favorite.path) {
            loadedIcon = await FlixIconProvider.loadIcon(forPath: favorite.path, policy: state.readPolicy)
        }
        .accessibilityHint(Text(favorite.kind == .folder ? .flixFavoriteFolderHint : .flixFavoriteAppHint))
    }

    /// Only Flix's own drags land here; a folder or app favorite takes them.
    private var accepts: Bool { state.drag != nil && favorite.kind != .file }

    /// The type icon, from the favorite's kind and name alone: nothing here reads the disk.
    private var icon: NSImage {
        let item = FlixItem(path: favorite.path, name: favorite.name,
                            kind: favorite.kind == .folder ? .folder : .other, activity: .opened, date: .distantPast)
        return FlixIconProvider.icon(for: item, policy: state.readPolicy)
    }
}
