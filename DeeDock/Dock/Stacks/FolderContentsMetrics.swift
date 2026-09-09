import Foundation

/// Count and size of a folder's contents.
///
/// Immediate count matches `FolderStackLoader`: visible children only. Packages,
/// aliases, and symbolic links count as one item each. Recursive count includes
/// those same kinds of items in descendants and does not count files inside a
/// package. Total size sums file bytes, including files inside packages.
///
/// A directory entry's own `fileSize` is never a contents total.
nonisolated struct FolderContentsMetrics: Equatable, Sendable {
    /// Whether the walk finished, and whether every descendant was readable.
    enum Completeness: Equatable, Sendable {
        /// The walk is still running. Size must not be shown as a finished total.
        case calculating
        /// Every visible descendant was measured.
        case complete
        /// The walk finished, but at least one descendant was skipped.
        case incomplete
    }

    /// Visible immediate children, after hidden files are omitted.
    var immediateItemCount: Int?
    /// Visible items at every depth, excluding package internals.
    var recursiveItemCount: Int?
    /// Sum of file bytes. `nil` until a finished walk publishes a total.
    var totalByteCount: Int64?
    var completeness: Completeness

    /// Finished walks, including incomplete ones that still have a measured total.
    var isFinal: Bool { completeness != .calculating }

    /// Size used for Size sort. Calculating folders stay unknown so they do not jump mid-walk.
    var sortByteCount: Int64? {
        guard isFinal else { return nil }
        return totalByteCount
    }

    init(immediateItemCount: Int? = nil, recursiveItemCount: Int? = nil,
         totalByteCount: Int64? = nil, completeness: Completeness) {
        self.immediateItemCount = immediateItemCount
        self.recursiveItemCount = recursiveItemCount
        self.totalByteCount = totalByteCount
        self.completeness = completeness
    }

    /// In-progress metrics, optionally with an immediate child count already known.
    static func calculating(immediateItemCount: Int? = nil) -> FolderContentsMetrics {
        FolderContentsMetrics(immediateItemCount: immediateItemCount, completeness: .calculating)
    }
}
