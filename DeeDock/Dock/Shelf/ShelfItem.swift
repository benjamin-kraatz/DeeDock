import Foundation

/// One file staged on the Shelf.
///
/// The Shelf never copies or moves anything: an item is a reference to a file that stays exactly
/// where the user left it. Removing an item, here or by dropping it on Trash, discards this
/// reference and leaves the file untouched.
nonisolated struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    /// Stable view and drag identity. Moving or renaming the file does not change it.
    let id: UUID
    /// Last known location, used when bookmark resolution is unavailable.
    let url: URL
    /// Finder-provided name retained while the file is unavailable.
    let name: String
    /// Persistent read access created from a user-initiated Finder drop.
    var bookmarkData: Data
    /// Most recent staging or restoration time. Also starts the Compost age threshold.
    var addedAt: Date
    /// Affects wording and icon only; the Shelf treats folders and files the same way.
    let isDirectory: Bool

    init(id: UUID = UUID(), url: URL, name: String, bookmarkData: Data,
         addedAt: Date = Date(), isDirectory: Bool = false) {
        self.id = id
        self.url = url
        self.name = name
        self.bookmarkData = bookmarkData
        self.addedAt = addedAt
        self.isDirectory = isDirectory
    }
}

/// How the panel arranges staged items. Date and name are flat orders; Smart creates sections.
nonisolated enum ShelfSort: String, Codable, CaseIterable, Sendable {
    case dateAdded
    case name
    case smart

    var title: LocalizedStringResource {
        switch self {
        case .dateAdded: .shelfSortDateAdded
        case .name: .shelfSortName
        case .smart: .semanticStackSmart
        }
    }

    var symbol: String {
        switch self {
        case .dateAdded: "clock"
        case .name: "textformat.abc"
        case .smart: "sparkles"
        }
    }
}

/// How the panel lays the staged items out.
nonisolated enum ShelfPresentation: String, Codable, CaseIterable, Sendable {
    case list
    case grid
}

/// The persisted Shelf. One shared bin, independent of display and of the active Dock Mode.
nonisolated struct ShelfDocument: Codable, Equatable, Sendable {
    /// Version 2 adds Compost. Older apps must refuse it rather than discard the archive.
    static let currentVersion = 2
    /// Refusing a larger batch keeps the panel usable and the drag image meaningful.
    static let capacity = 50

    var version: Int
    var items: [ShelfItem]
    var sort: ShelfSort
    var presentation: ShelfPresentation
    var compost: [ShelfCompostEntry]
    var compostPolicy: ShelfCompostPolicy

    init(version: Int = ShelfDocument.currentVersion, items: [ShelfItem] = [],
         sort: ShelfSort = .dateAdded, presentation: ShelfPresentation = .list,
         compost: [ShelfCompostEntry] = [], compostPolicy: ShelfCompostPolicy = .off) {
        self.version = version
        self.items = items
        self.sort = sort
        self.presentation = presentation
        self.compost = compost
        self.compostPolicy = compostPolicy
    }

    /// Both view choices default rather than fail, so an older document still opens.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == 1 || version == Self.currentVersion else {
            throw CocoaError(.coderReadCorrupt)
        }
        items = try values.decode([ShelfItem].self, forKey: .items)
        sort = try values.decodeIfPresent(ShelfSort.self, forKey: .sort) ?? .dateAdded
        presentation = try values.decodeIfPresent(ShelfPresentation.self, forKey: .presentation) ?? .list
        if version == 1 {
            compost = []
            compostPolicy = .off
            version = Self.currentVersion
        } else {
            // Missing archive data in a current document is corruption, never an empty archive.
            compost = try values.decode([ShelfCompostEntry].self, forKey: .compost)
            compostPolicy = try values.decode(ShelfCompostPolicy.self, forKey: .compostPolicy)
        }
    }

    /// The staged items in the order the panel shows them.
    func ordered() -> [ShelfItem] {
        switch sort {
        case .dateAdded: items.sorted { $0.addedAt > $1.addedAt }
        case .name, .smart: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// A document that fails this is reported rather than silently read as an empty Shelf.
    var isValid: Bool {
        guard version == Self.currentVersion, items.count <= Self.capacity,
              compost.count <= ShelfCompostEntry.capacity else { return false }
        let all = items + compost.map(\.item)
        return Set(all.map(\.id)).count == all.count
    }
}
