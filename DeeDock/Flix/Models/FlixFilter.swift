import Foundation

/// What the sidebar has selected, which decides the list before search narrows it.
nonisolated enum FlixFilter: Hashable, Sendable {
    /// The Activity section: All, Opened, Downloaded, New, Saved, Links, Flagged.
    nonisolated enum Activity: String, CaseIterable, Sendable {
        case all, opened, downloaded, created, saved
        /// Web pages (phase B1). The sidebar shows it while web links are on or links exist.
        case links
        case flagged
    }

    /// The Kinds section.
    nonisolated enum Kind: String, CaseIterable, Sendable {
        case screenshots, images, documents
        /// Google Docs, Figma, Notion, Linear, Office, and Atlassian pages (phase B1).
        case webDocuments
        case folders, apps
    }

    case activity(Activity)
    case kind(Kind)
    /// A phase B2 Thread, by its identifier.
    case thread(String)
    case smart(UUID)
    /// A folder favorite: everything inside that folder.
    case favorite(UUID)

    static let all = FlixFilter.activity(.all)

    /// Whether `item` passes this filter. Smart, favorite and thread filters need their definitions,
    /// which the caller supplies.
    func matches(_ item: FlixItem, smartFilters: [FlixSmartFilter], favorites: [FlixFavorite],
                 threadMembers: Set<FlixItem.ID>?, now: Date,
                 semantic: (String, FlixItem) -> Bool? = { _, _ in nil }) -> Bool {
        switch self {
        case .activity(let activity): activity.matches(item)
        case .kind(let kind): kind.matches(item)
        case .thread: threadMembers?.contains(item.id) ?? false
        case .smart(let id): smartFilters.first { $0.id == id }?.matches(item, now: now, semantic: semantic) ?? false
        case .favorite(let id):
            favorites.first { $0.id == id }.map { $0.kind == .folder && item.isInside($0.path) } ?? false
        }
    }
}

extension FlixFilter.Activity {
    nonisolated func matches(_ item: FlixItem) -> Bool {
        switch self {
        case .all: true
        case .opened: item.activity == .opened
        case .downloaded: item.activity == .downloaded
        case .created: item.activity == .created
        case .saved: item.activity == .saved
        case .links: item.kind == .link
        case .flagged: item.isFlagged
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .all: .flixFilterAll
        case .opened: .flixFilterOpened
        case .downloaded: .flixFilterDownloaded
        case .created: .flixFilterNew
        case .saved: .flixFilterSaved
        case .links: .flixFilterLinks
        case .flagged: .flixFilterFlagged
        }
    }

    var symbol: String {
        switch self {
        case .all: "circle.dotted.circle"
        case .opened: "arrow.up.right"
        case .downloaded: "arrow.down"
        case .created: "plus"
        case .saved: "pencil"
        case .links: "link"
        case .flagged: "flag.fill"
        }
    }
}

extension FlixFilter.Kind {
    nonisolated func matches(_ item: FlixItem) -> Bool {
        switch self {
        case .screenshots: item.kind == .screenshot
        case .images: item.kind == .image || item.kind == .screenshot
        case .documents: item.kind == .document
        case .webDocuments: item.link.map { FlixWebDocuments.isWebDocument($0.url) } ?? false
        case .folders: item.kind == .folder
        case .apps: item.kind == .app
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .screenshots: .flixKindScreenshots
        case .images: .flixKindImages
        case .documents: .flixKindDocuments
        case .webDocuments: .flixKindWebDocuments
        case .folders: .flixKindFolders
        case .apps: .flixKindApps
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .images: "photo"
        case .documents: "doc.text"
        case .webDocuments: "doc.richtext"
        case .folders: "folder"
        case .apps: "app"
        }
    }
}
