import Foundation

/// The presentation chosen for one pinned folder on one display.
nonisolated enum FolderStackPresentation: String, Codable, CaseIterable, Sendable {
    case grid
    case list
}

/// A persistable folder identity with user-granted read access.
nonisolated struct FolderReference: Codable, Equatable, Identifiable, Sendable {
    /// Stable view and drag identity. Moving or renaming the folder does not change it.
    let id: UUID
    /// Last known location, used when bookmark resolution is unavailable.
    let url: URL
    /// Finder-provided name retained while the folder is unavailable.
    let name: String
    /// Persistent read access created from a user-initiated Finder drop.
    var bookmarkData: Data
    /// Presentation local to this display's pin.
    var presentation: FolderStackPresentation

    init(id: UUID = UUID(), url: URL, name: String, bookmarkData: Data,
         presentation: FolderStackPresentation = .grid) {
        self.id = id
        self.url = url
        self.name = name
        self.bookmarkData = bookmarkData
        self.presentation = presentation
    }
}
