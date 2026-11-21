import Foundation

/// Everything Settings → Features → Flix Files controls. Persisted as JSON under
/// `flix.settings.v1` (`FlixSettingsRepository`).
///
/// Keys missing from saved data decode to their defaults, so adding a field never loses the rest.
/// Defaults: Flix Files on with its dock tile, the menu bar item off, Control-Option-Command-F,
/// web links and "pages you read" off, Flix Pick on. Intelligence switches default on but do
/// nothing until phase B's providers exist and their engines are available; they never send
/// anything off the Mac except Ask Robi, which only runs when asked.
nonisolated struct FlixSettings: Codable, Equatable, Sendable {
    // MARK: Where it lives
    var isEnabled = true
    var showsDockTile = true
    var showsMenuBarItem = false
    var shortcutEnabled = true
    var shortcut = FlixShortcutCombo.default
    var onOpen = FlixOnOpenAction.nothing
    var afterDrag = FlixAfterDragAction.close

    // MARK: What it tracks
    var tracksOpenedFiles = true
    /// New, saved, and downloaded files inside ``watchedFolders``.
    var tracksWatchedFolders = true
    var tracksFolders = true
    var tracksApps = true
    var watchedFolders: [FlixWatchedFolder] = FlixPaths.defaultWatchedFolders().map { FlixWatchedFolder(path: $0) }

    // MARK: Web links (phase B1)
    /// Off by default. Phase B1 implements the tracking itself.
    var tracksLinks = false
    /// "Pages you read": pages that stay in front at least two minutes. A separate opt-in.
    var tracksPagesYouRead = false
    /// Banking and health sites are never tracked while this is on.
    var excludesSensitiveSites = true
    /// Hosts never tracked, as typed ("bank.example.com").
    var excludedSites: [String] = []
    /// Fetch site icons for link rows. Off draws a monogram and makes no request.
    var fetchesSiteIcons = false

    // MARK: Intelligence (phase B)
    var suggestsForFrontWindow = true
    var showsFitsOnTile = true
    var writesCaptions = true
    var groupsThreads = true
    var suggestsFolders = true
    var guardsSensitiveFiles = true
    var hidesNoise = true
    var learnsDragDestinations = true

    // MARK: Flix Pick
    /// Shows Flix Pick beside other apps' Open and Save pickers. Needs Accessibility permission.
    var showsFlixPick = true
    /// Bundle identifiers of apps where Flix Pick stays hidden ("Not in <App>").
    var flixPickExcludedApps: [String] = []

    init() {}

    /// The watched folders that are switched on.
    var enabledWatchedFolders: [FlixWatchedFolder] { watchedFolders.filter(\.isEnabled) }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, showsDockTile, showsMenuBarItem, shortcutEnabled, shortcut, onOpen, afterDrag
        case tracksOpenedFiles, tracksWatchedFolders, tracksFolders, tracksApps, watchedFolders
        case tracksLinks, tracksPagesYouRead, excludesSensitiveSites, excludedSites, fetchesSiteIcons
        case suggestsForFrontWindow, showsFitsOnTile, writesCaptions, groupsThreads, suggestsFolders
        case guardsSensitiveFiles, hidesNoise, learnsDragDestinations
        case showsFlixPick, flixPickExcludedApps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FlixSettings()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        showsDockTile = try c.decodeIfPresent(Bool.self, forKey: .showsDockTile) ?? d.showsDockTile
        showsMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showsMenuBarItem) ?? d.showsMenuBarItem
        shortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortcutEnabled) ?? d.shortcutEnabled
        shortcut = (try? c.decodeIfPresent(FlixShortcutCombo.self, forKey: .shortcut)) ?? d.shortcut
        onOpen = (try? c.decodeIfPresent(FlixOnOpenAction.self, forKey: .onOpen)) ?? d.onOpen
        afterDrag = (try? c.decodeIfPresent(FlixAfterDragAction.self, forKey: .afterDrag)) ?? d.afterDrag
        tracksOpenedFiles = try c.decodeIfPresent(Bool.self, forKey: .tracksOpenedFiles) ?? d.tracksOpenedFiles
        tracksWatchedFolders = try c.decodeIfPresent(Bool.self, forKey: .tracksWatchedFolders) ?? d.tracksWatchedFolders
        tracksFolders = try c.decodeIfPresent(Bool.self, forKey: .tracksFolders) ?? d.tracksFolders
        tracksApps = try c.decodeIfPresent(Bool.self, forKey: .tracksApps) ?? d.tracksApps
        watchedFolders = try c.decodeIfPresent([FlixWatchedFolder].self, forKey: .watchedFolders) ?? d.watchedFolders
        tracksLinks = try c.decodeIfPresent(Bool.self, forKey: .tracksLinks) ?? d.tracksLinks
        tracksPagesYouRead = try c.decodeIfPresent(Bool.self, forKey: .tracksPagesYouRead) ?? d.tracksPagesYouRead
        excludesSensitiveSites = try c.decodeIfPresent(Bool.self, forKey: .excludesSensitiveSites)
            ?? d.excludesSensitiveSites
        excludedSites = try c.decodeIfPresent([String].self, forKey: .excludedSites) ?? d.excludedSites
        fetchesSiteIcons = try c.decodeIfPresent(Bool.self, forKey: .fetchesSiteIcons) ?? d.fetchesSiteIcons
        suggestsForFrontWindow = try c.decodeIfPresent(Bool.self, forKey: .suggestsForFrontWindow)
            ?? d.suggestsForFrontWindow
        showsFitsOnTile = try c.decodeIfPresent(Bool.self, forKey: .showsFitsOnTile) ?? d.showsFitsOnTile
        writesCaptions = try c.decodeIfPresent(Bool.self, forKey: .writesCaptions) ?? d.writesCaptions
        groupsThreads = try c.decodeIfPresent(Bool.self, forKey: .groupsThreads) ?? d.groupsThreads
        suggestsFolders = try c.decodeIfPresent(Bool.self, forKey: .suggestsFolders) ?? d.suggestsFolders
        guardsSensitiveFiles = try c.decodeIfPresent(Bool.self, forKey: .guardsSensitiveFiles) ?? d.guardsSensitiveFiles
        hidesNoise = try c.decodeIfPresent(Bool.self, forKey: .hidesNoise) ?? d.hidesNoise
        learnsDragDestinations = try c.decodeIfPresent(Bool.self, forKey: .learnsDragDestinations)
            ?? d.learnsDragDestinations
        showsFlixPick = try c.decodeIfPresent(Bool.self, forKey: .showsFlixPick) ?? d.showsFlixPick
        flixPickExcludedApps = try c.decodeIfPresent([String].self, forKey: .flixPickExcludedApps)
            ?? d.flixPickExcludedApps
    }
}

/// What opening Flix Files does besides showing the panel.
nonisolated enum FlixOnOpenAction: String, Codable, CaseIterable, Sendable {
    case nothing
    /// Copies the newest item, as Finder's Copy does.
    case copyNewest
    /// Copies the newest item's path as text.
    case copyNewestPath

    var title: LocalizedStringResource {
        switch self {
        case .nothing: .flixOnOpenNothing
        case .copyNewest: .flixOnOpenCopyNewest
        case .copyNewestPath: .flixOnOpenCopyPath
        }
    }
}

/// Whether the panel closes after something was dragged out of it and dropped elsewhere.
nonisolated enum FlixAfterDragAction: String, Codable, CaseIterable, Sendable {
    case close
    case stayOpen

    var title: LocalizedStringResource {
        switch self {
        case .close: .flixAfterDragClose
        case .stayOpen: .flixAfterDragStay
        }
    }
}

/// A folder Flix Files watches for new, saved, and downloaded files.
nonisolated struct FlixWatchedFolder: Codable, Identifiable, Hashable, Sendable {
    var path: String
    var isEnabled: Bool
    /// What DOKK last learned about reading it. Only an explicit request (the **Allow…** button)
    /// changes `unknown`, because reading a protected folder makes macOS ask.
    var access: FlixFolderAccessState

    var id: String { path }

    init(path: String, isEnabled: Bool = true, access: FlixFolderAccessState = .unknown) {
        self.path = FlixPaths.standardized(path)
        self.isEnabled = isEnabled
        self.access = access
    }
}

/// Whether DOKK may read a watched folder, as far as it knows.
nonisolated enum FlixFolderAccessState: String, Codable, Sendable {
    /// Never asked. A protected folder stays unwatched until you allow it.
    case unknown
    case allowed
    /// macOS said no, or the folder cannot be read.
    case denied
    /// The folder is not there.
    case missing
}
