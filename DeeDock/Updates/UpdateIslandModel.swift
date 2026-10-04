#if DIRECT_DISTRIBUTION
import Foundation
import Observation

/// What a compact island announces.
struct UpdateIslandAnnouncement: Equatable {
    enum Kind: Equatable {
        /// A scheduled offer that needs the user to download or approve it.
        case available
        /// A silently downloaded offer that idle install has not reached yet.
        case ready
        /// An automatic install finished. `version` is the running version.
        case installed
    }

    let kind: Kind
    let version: String
}

/// State the island's owner drives from outside the view tree.
@MainActor
@Observable
final class UpdateIslandModel {
    enum Content: Equatable {
        /// Compact, dismissible notice.
        case callout(UpdateIslandAnnouncement)
        /// The full update panel, rendering the shared `UpdatePresentation`.
        case panel
    }

    /// Changing this morphs the open island; it never goes from `.panel` back to a callout.
    var content: Content
    /// True once the island should fold up and leave. The owner closes the panel after
    /// `UpdateIslandView.departureDuration(reduceMotion:)`.
    var isLeaving = false

    init(content: Content) {
        self.content = content
    }
}
#endif
