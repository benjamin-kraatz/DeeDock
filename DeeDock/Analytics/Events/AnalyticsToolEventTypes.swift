import Foundation

// Closed vocabularies for tool events: Shortcut tiles, Window Search, Fusion, the file handoff
// panel, and Launcher suggestions. Every value is a compile-time constant.

/// Where a pinned Shortcut was run from.
nonisolated enum AnalyticsShortcutSource: String, AnalyticsToken {
    /// A click on the dock tile, or VoiceOver's default action on it.
    case tile
    /// Return while the dock has keyboard focus.
    case keyboard
    /// Files dropped on the tile.
    case drop
    /// A Launcher search result.
    case launcher
    /// A Launcher file action, with the Launcher's files as input.
    case launcherFiles = "launcher_files"
    /// The Run button in Settings.
    case settings
}

nonisolated enum AnalyticsShortcutTileAction: String, AnalyticsToken {
    case pinned, unpinned, moved, acceptsFilesOn = "accepts_files_on", acceptsFilesOff = "accepts_files_off", reset
}

/// Why a Window Search result matched.
nonisolated enum AnalyticsWindowSearchEvidence: String, AnalyticsToken {
    case metadata, text, capsule, historicalOCR = "historical_ocr", image

    init(_ evidence: WindowSearchEvidence) {
        switch evidence {
        case .metadata: self = .metadata
        case .text: self = .text
        case .capsule: self = .capsule
        case .historicalOCR: self = .historicalOCR
        case .image: self = .image
        }
    }
}

/// One step of a Fusion run.
nonisolated enum AnalyticsFusionStep: String, AnalyticsToken {
    case capture, generate, save
}

nonisolated enum AnalyticsFusionFailure: String, AnalyticsToken {
    case modelUnavailable = "model_unavailable", contextLimit = "context_limit", refused
    case invalidOutput = "invalid_output", timeout, captureDenied = "capture_denied"
    case captureFailed = "capture_failed", saveFailed = "save_failed"

    init(_ failure: FusionFailure) {
        switch failure {
        case .modelUnavailable: self = .modelUnavailable
        case .contextLimit: self = .contextLimit
        case .refused: self = .refused
        case .invalidOutput: self = .invalidOutput
        case .timeout: self = .timeout
        case .captureDenied: self = .captureDenied
        case .captureFailed: self = .captureFailed
        case .saveFailed: self = .saveFailed
        }
    }
}

/// A step in the panel that routes dropped files to a window or app.
nonisolated enum AnalyticsFileHandoffAction: String, AnalyticsToken {
    /// The panel opened and the files were checked.
    case shown
    /// The target window or app was brought forward.
    case activated
    /// File references were copied to the clipboard.
    case copied
    /// The files were opened with the app.
    case opened
}

nonisolated enum AnalyticsSuggestionFeedback: String, AnalyticsToken {
    case useful, notNow = "not_now"

    init(_ kind: LauncherSuggestionFeedback.Kind) {
        switch kind {
        case .useful: self = .useful
        case .notNow: self = .notNow
        }
    }
}

/// The answer to the Launcher's "Were these suggestions useful?" prompt.
nonisolated enum AnalyticsSuggestionPromptAnswer: String, AnalyticsToken {
    case useful, notUseful = "not_useful", noAnswer = "no_answer"

    init(_ useful: Bool?) {
        switch useful {
        case true?: self = .useful
        case false?: self = .notUseful
        case nil: self = .noAnswer
        }
    }
}

/// App-wide feature preferences that live outside the dock, atmosphere, menu-bar, and update
/// settings models. Each is reported through `setting_changed` with `area = features`.
nonisolated enum AnalyticsFeatureSetting: String, AnalyticsToken {
    case discoveryEnabled = "discovery_enabled"
    case launcherSuggestionsEnabled = "launcher_suggestions_enabled"
    case launcherSuggestionsPaused = "launcher_suggestions_paused"
    case launcherSuggestionPromptsEnabled = "launcher_suggestion_prompts_enabled"
    case clipboardRedactSecrets = "clipboard_redact_secrets"
    case clipboardCuratorEnabled = "clipboard_curator_enabled"
    case localHistoryRecording = "local_history_recording"
    case localHistoryReplay = "local_history_replay"
    case peekHistoryEnabled = "peek_history_enabled"
    case shelfSort = "shelf_sort"
    case shelfPresentation = "shelf_presentation"
    /// Days after which unused Shelf items move to compost; 0 is off.
    case shelfCompostDays = "shelf_compost_days"
    /// The macOS Dock switch, changed by a click in Settings or the tour. Quit and launch
    /// follow-through is reported by `system_dock_tuck`, not here.
    case systemDockTuck = "system_dock_tuck"
    /// Lookout's "Search by content" switch in Settings.
    case lookoutEnabled = "lookout_enabled"
    /// Lookout's "Read files on battery too" in Settings.
    case lookoutIndexOnBattery = "lookout_index_on_battery"
    /// How many folders Lookout reads, after one was added or removed in Settings.
    case lookoutFolderCount = "lookout_folder_count"
}

/// Which window permissions Harbor had when it opened.
nonisolated enum AnalyticsHarborAccess: String, AnalyticsToken {
    case full, accessibilityOnly = "accessibility_only", screenRecordingOnly = "screen_recording_only", none

    init(_ access: HarborAccess) {
        switch (access.windows, access.thumbnails) {
        case (true, true): self = .full
        case (true, false): self = .accessibilityOnly
        case (false, true): self = .screenRecordingOnly
        case (false, false): self = .none
        }
    }
}

/// How Harbor closed.
nonisolated enum AnalyticsHarborOutcome: String, AnalyticsToken {
    /// A window was brought forward.
    case window
    /// An app was brought forward without an exact window.
    case app
    /// A minimized or hidden window was restored.
    case restored
    /// Escape, a click on the wallpaper, the shortcut, or the tile closed it.
    case dismissed
    /// Another app, a Space change, sleep, or Settings took over.
    case interrupted
}

/// What opened the DOKK Hub.
nonisolated enum AnalyticsHubTrigger: String, AnalyticsToken {
    /// A click on the DOKK tile, or VoiceOver's default action on it.
    case tile
    /// Return on the DOKK tile while Focus Dock has keyboard focus.
    case focusDock = "focus_dock"
    /// Files dropped on the DOKK tile or handed over from the Shelf.
    case fileDrop = "file_drop"
    /// Open in Hub on a folder stack, the Downloads stack, or a drive.
    case openFolder = "open_folder"
    /// Lookout's settings asked for its onboarding, which shows over the Hub.
    case lookoutSetup = "lookout_setup"
    /// DOKK relaunched for Full Disk Access and reopened an uninstall sheet in the Apps tab.
    case uninstallRelaunch = "uninstall_relaunch"
}

/// How a Hub tab was chosen.
nonisolated enum AnalyticsHubTabSwitch: String, AnalyticsToken {
    case click, keyboard
}

/// How an uninstall from the Hub's Apps tab ended.
nonisolated enum AnalyticsUninstallOutcome: String, AnalyticsToken {
    /// The app and every selected item are in the Trash.
    case completed
    /// The app is in the Trash; some selected items aren't.
    case partial
    /// The sheet closed before anything was removed.
    case dismissed
    /// DOKK relaunched so a Full Disk Access grant applies.
    case relaunched
    /// The user cancelled Finder's password prompt, and the sheet closed.
    case passwordCancelled = "password_cancelled"
    /// The app didn't quit, and the sheet closed.
    case stillOpen = "still_open"
    /// macOS refused to move the app, and the sheet closed.
    case failed

    /// Whether the app itself went to the Trash.
    var removedApp: Bool { self == .completed || self == .partial }
}

/// Where an uninstalled app came from. Never which app.
nonisolated enum AnalyticsUninstallSource: String, AnalyticsToken {
    case appStore = "app_store", testFlight = "test_flight", installer, downloaded, unknown
}

nonisolated enum AnalyticsHubTransferKind: String, AnalyticsToken {
    case copy, move
}

nonisolated enum AnalyticsHubTransferOutcome: String, AnalyticsToken {
    case completed, cancelled, failed
}

/// The Files tab's view style.
nonisolated enum AnalyticsHubFilesView: String, AnalyticsToken {
    case list, icons, columns
}

/// What changed in the Files sidebar's Favorites.
nonisolated enum AnalyticsHubSidebarAction: String, AnalyticsToken {
    case add, remove, reorder, restore, undo
}

/// How a Files sidebar change was made.
nonisolated enum AnalyticsHubSidebarMethod: String, AnalyticsToken {
    case drag, menu, shortcut, accessibility, toast, popover, settings
    case dragOut = "drag_out"
    case headerMenu = "header_menu"
}

/// Where a Files tab search looked.
nonisolated enum AnalyticsHubSearchScope: String, AnalyticsToken {
    case thisMac = "this_mac", folder
}

/// Which part of the Files search results an opened result was in.
nonisolated enum AnalyticsLookoutSection: String, AnalyticsToken {
    /// Spotlight's name results.
    case names
    /// Lookout's strong hits, shown at once.
    case strong
    /// Lookout's weaker hits, inside the "Weaker matches" fold.
    case weak
}

/// What a Lookout hit is.
nonisolated enum AnalyticsLookoutKind: String, AnalyticsToken {
    case screenshot, image, pdf, doc, folder
}

/// Why a Lookout hit qualified.
nonisolated enum AnalyticsLookoutMatch: String, AnalyticsToken {
    case meaning, words, both
}

/// What a Files search that opened a result searched with.
nonisolated enum AnalyticsLookoutQuery: String, AnalyticsToken {
    /// Typed words.
    case text
    /// A picture, or a file's stored vector (Find Similar).
    case image
}

/// Where a search with a picture came from.
nonisolated enum AnalyticsLookoutImageSource: String, AnalyticsToken {
    /// Dropped on the search field.
    case drop
    /// Pasted into the search field.
    case paste
    /// Find Similar on a result (the button, the menu, ⌘⇧L, or dragging the row onto the field).
    case similar
    /// Find Similar on a file in the Files tab's browser (the button, the menu, or ⌘⇧L).
    case browser
    /// Find Similar in the Apps tab's file actions, for a file dropped on the DOKK tile or the Apps tab.
    case hubTile = "hub_tile"
}

/// A step of Lookout's onboarding (`LookoutSetupStep`).
nonisolated enum AnalyticsLookoutSetupStep: String, AnalyticsToken {
    case welcome, folders, access, download, firstPass = "first_pass"
}

/// How one run of Lookout's model download ended.
nonisolated enum AnalyticsLookoutDownloadOutcome: String, AnalyticsToken {
    case completed, failed, cancelled
}

/// Why Lookout's model download failed (`LookoutDownloadError`).
nonisolated enum AnalyticsLookoutDownloadError: String, AnalyticsToken {
    case network, server, host, checksum, incomplete, write, diskSpace = "disk_space"
}

/// macOS's answer when Lookout asked to read a folder.
nonisolated enum AnalyticsLookoutAccessOutcome: String, AnalyticsToken {
    case allowed, denied
}

/// Where Lookout asked to read a folder.
nonisolated enum AnalyticsLookoutAccessContext: String, AnalyticsToken {
    case onboarding, settings
}

/// Where a plugin action came from.
nonisolated enum AnalyticsPluginSurface: String, AnalyticsToken {
    /// The plugin tile's menu or its VoiceOver actions.
    case tile
    /// The plugin's panel: its stopped state or its More menu.
    case panel
    /// The Plugins page in Settings.
    case settings
    /// DOKK did it on its own, such as pinning a newly approved plugin.
    case automatic
}
