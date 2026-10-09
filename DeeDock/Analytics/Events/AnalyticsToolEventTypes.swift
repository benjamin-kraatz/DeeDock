import Foundation

// Closed vocabularies for tool events: Shortcut tiles, Window Search, Fusion, portals, the file
// handoff panel, and Launcher suggestions. Every value is a compile-time constant.

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

/// What a person did with a pinned portal after pinning it.
nonisolated enum AnalyticsPortalAction: String, AnalyticsToken {
    case paused, resumed, frozen, frameSaved = "frame_saved", cropOpened = "crop_opened", jumped
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
    case badgeMemoryCollectFocus = "badge_memory_collect_focus"
    case shelfSort = "shelf_sort"
    case shelfPresentation = "shelf_presentation"
    /// Days after which unused Shelf items move to compost; 0 is off.
    case shelfCompostDays = "shelf_compost_days"
    /// The macOS Dock switch, changed by a click in Settings or the tour. Quit and launch
    /// follow-through is reported by `system_dock_tuck`, not here.
    case systemDockTuck = "system_dock_tuck"
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
}

/// How a Hub tab was chosen.
nonisolated enum AnalyticsHubTabSwitch: String, AnalyticsToken {
    case click, keyboard
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

/// Where a Files tab search looked.
nonisolated enum AnalyticsHubSearchScope: String, AnalyticsToken {
    case thisMac = "this_mac", folder
}
