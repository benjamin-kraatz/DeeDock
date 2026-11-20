import AppKit
import Observation

/// What every display's Flix Files tile draws, shared so a new item redraws the tiles alone instead
/// of rebuilding the docks.
///
/// `FlixCoordinator` keeps it current from the history and `FlixIntelligence`. The thumbnail is
/// loaded once per newest item; it is a Quick Look thumbnail only when the read policy allows reading
/// that file, otherwise the type's icon, so the tile never makes macOS ask for folder access.
@MainActor @Observable
final class FlixTileState {
    /// The item a drag of the tile carries and the thumbnail shows.
    private(set) var newest: FlixItem?
    /// Drawn on the tile; nil until loaded.
    private(set) var thumbnail: NSImage?
    /// The red badge: items that arrived since the panel was last opened.
    private(set) var unseenCount = 0
    /// The purple "✦ N fit here" pill. Nil hides it.
    var fitCount: Int?
    /// The open dot under the tile.
    var isPanelOpen = false
    /// Counts arrivals, so each one plays the tile's pop once.
    private(set) var arrivals = 0
    /// The newest item's preview is blurred because it looks sensitive.
    private(set) var newestIsSensitive = false

    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?

    init() {}

    /// For previews: a fixed tile without loading anything.
    init(preview newest: FlixItem?, thumbnail: NSImage?, unseen: Int, fits: Int?) {
        self.newest = newest
        self.thumbnail = thumbnail
        unseenCount = unseen
        fitCount = fits
    }

    /// Updates from the history. Loads a new thumbnail only when the newest item changed.
    func update(newest item: FlixItem?, unseen: Int, sensitive: Bool, policy: FlixReadPolicy) {
        if unseen > unseenCount { arrivals += 1 }
        unseenCount = unseen
        newestIsSensitive = sensitive
        guard item?.id != newest?.id || item?.date != newest?.date else { return }
        newest = item
        thumbnailTask?.cancel()
        guard let item else { thumbnail = nil; return }
        thumbnail = FlixIconProvider.typeIcon(for: item)
        guard let url = item.url, let path = item.path, policy.canRead(path) else { return }
        thumbnailTask = Task { [weak self] in
            let image = await HubThumbnailCache.shared.thumbnail(for: url, size: CGSize(width: 64, height: 64),
                                                                 scale: NSScreen.main?.backingScaleFactor ?? 2)
            guard let self, !Task.isCancelled, newest?.id == item.id, let image else { return }
            thumbnail = image
        }
    }

    func stop() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }
}
