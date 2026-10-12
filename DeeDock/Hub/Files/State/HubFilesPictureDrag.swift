import AppKit

/// Whether a drag is over the Hub, pieced together from every place that hears about it: the observer over the whole
/// Hub (`HubDragObserver`), the search field, and the Files tab's own drop regions (`HubFilesInteractionView`). Each
/// reports entering and leaving under its own key; the drag is over the Hub while any of them holds it.
///
/// Moving from one region to the next reports leaving one before entering the other, so the end waits `grace` and a
/// new entry cancels it: the well doesn't flicker between rows. A drag that ends (dropped or cancelled) ends at once.
/// The pending end is the only task, and `reset` cancels it. Main actor.
@MainActor
final class HubFilesPictureDrag {
    /// How long the drag may be between regions before it counts as gone.
    static let grace: Duration = .milliseconds(150)

    /// The drag started in the Files tab: in a pane (moving files), or on a search result (dragging it onto the
    /// field runs Find Similar).
    enum Origin: Equatable {
        case outside
        case filesPane
        case searchResult
    }

    private(set) var origin: Origin = .outside
    /// The current drag's classification, read once per drag pasteboard change.
    private(set) var drop: LookoutPictureDrop?
    private var classifiedChangeCount: Int?
    private var inside: Set<String> = []
    private var pendingEnd: Task<Void, Never>?

    var isActive: Bool { !inside.isEmpty || pendingEnd != nil }

    /// A drag began in the Files tab.
    func began(_ origin: Origin) {
        self.origin = origin
    }

    /// `key` heard the drag enter.
    ///
    /// - Returns: True when the drag wasn't over the Hub before (the well should open).
    func enter(_ key: String) -> Bool {
        let wasActive = isActive
        pendingEnd?.cancel()
        pendingEnd = nil
        inside.insert(key)
        return !wasActive
    }

    /// `key` heard the drag leave. When nothing holds it any more, `ended` runs after `grace` unless something
    /// hears it enter first.
    func exit(_ key: String, ended: @escaping @MainActor () -> Void) {
        inside.remove(key)
        guard inside.isEmpty, pendingEnd == nil else { return }
        pendingEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.grace)
            guard !Task.isCancelled, let self else { return }
            pendingEnd = nil
            guard inside.isEmpty else { return }
            ended()
        }
    }

    /// Classifies the drag on `pasteboard` unless its contents haven't changed since the last time.
    func classify(_ pasteboard: NSPasteboard, _ classify: (NSPasteboard) -> LookoutPictureDrop?) -> LookoutPictureDrop? {
        if classifiedChangeCount != pasteboard.changeCount {
            classifiedChangeCount = pasteboard.changeCount
            drop = classify(pasteboard)
        }
        return drop
    }

    /// The drag left the Hub (or was dropped): forget where it was and what it is. A drag that began in the Files
    /// tab keeps its origin until `sessionEnded`, in case it comes back.
    func reset() {
        pendingEnd?.cancel()
        pendingEnd = nil
        inside = []
        drop = nil
        classifiedChangeCount = nil
    }

    /// A drag that began in the Files tab ended.
    func sessionEnded() {
        reset()
        origin = .outside
    }

    isolated deinit { pendingEnd?.cancel() }
}
