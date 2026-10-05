import Foundation

// Closed vocabularies used by `AnalyticsEvent`. Every value is a compile-time constant.

/// What a stack shows.
nonisolated enum AnalyticsStackKind: String, AnalyticsToken {
    case downloads, folder, drive
}

nonisolated enum AnalyticsDropOperation: String, AnalyticsToken {
    case copy, move
}

/// Where files were dropped.
nonisolated enum AnalyticsDropTarget: String, AnalyticsToken {
    case tile, stack
}

/// Whether an operation worked. Failures are reported as a code, never as message text.
nonisolated enum AnalyticsOutcome: String, AnalyticsToken, Sendable {
    case succeeded, failed, canceled, blocked, partial
}

nonisolated enum AnalyticsSmartGroupingSource: String, AnalyticsToken, Sendable {
    case folder, shelf
}

nonisolated enum AnalyticsSmartGroupingResult: String, AnalyticsToken, Sendable {
    case generated, cached, failed
}

/// Why smart grouping produced no groups.
nonisolated enum AnalyticsSmartGroupingFailure: String, AnalyticsToken, Sendable {
    case deviceNotEligible = "device_not_eligible"
    case appleIntelligenceNotEnabled = "apple_intelligence_not_enabled"
    case modelNotReady = "model_not_ready"
    case modelUnavailable = "model_unavailable"
    case generationFailed = "generation_failed"

    init(_ availability: SemanticStackAvailability) {
        switch availability {
        case .deviceNotEligible: self = .deviceNotEligible
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
        case .modelNotReady: self = .modelNotReady
        case .available: self = .modelUnavailable
        }
    }
}

nonisolated enum AnalyticsPeekTrigger: String, AnalyticsToken {
    case hover, keyboard, fileDrag = "file_drag"
}

nonisolated enum AnalyticsWindowAction: String, AnalyticsToken {
    case minimize, restore, close, move, left, right, center, fill, undo

    init(_ action: WindowAction) {
        switch action {
        case .minimized(let minimized): self = minimized ? .minimize : .restore
        case .close: self = .close
        case .undo: self = .undo
        case .place(let placement, _):
            switch placement {
            case .move: self = .move
            case .left: self = .left
            case .right: self = .right
            case .center: self = .center
            case .fill: self = .fill
            }
        }
    }
}

nonisolated enum AnalyticsMarkupAction: String, AnalyticsToken {
    case opened, saved, copied, sentToShelf = "sent_to_shelf", shared, copiedText = "copied_text"
    case searchedWeb = "searched_web", recaptured
}

nonisolated enum AnalyticsPortalSource: String, AnalyticsToken {
    case button, keyboard, drag, frozen
}

nonisolated enum AnalyticsWatchCompletion: String, AnalyticsToken {
    case none, openFolder = "open_folder", runShortcut = "run_shortcut"

    init(_ action: WindowWatchCompletionAction) {
        switch action {
        case .none: self = .none
        case .openFolder: self = .openFolder
        case .runShortcut: self = .runShortcut
        }
    }
}

nonisolated enum AnalyticsWatchDetection: String, AnalyticsToken {
    case change, phrase
}

nonisolated enum AnalyticsWatchEnd: String, AnalyticsToken {
    case stopped, permission, unavailable, closed, offscreen
}

nonisolated enum AnalyticsLauncherSource: String, AnalyticsToken {
    case tile, keyboard, fileDrop = "file_drop", shelf
}

nonisolated enum AnalyticsFileOperationStatus: String, AnalyticsToken {
    case completed, failed, partial
}

/// What started a Dock Mode switch.
nonisolated enum AnalyticsModeSource: String, AnalyticsToken {
    case menuBar = "menu_bar", picker, settings, launcher, prepareWorkspace = "prepare_workspace"
    case focusSession = "focus_session", previousMode = "previous_mode"
}

nonisolated enum AnalyticsModeEdit: String, AnalyticsToken {
    case created, duplicated, deleted, renamed, reordered, recipeUpdated = "recipe_updated"
    case snapshotSaved = "snapshot_saved"
}

nonisolated enum AnalyticsRecipeOutcome: String, AnalyticsToken {
    case succeeded, stoppedOnFailure = "stopped_on_failure", canceled, noSteps = "no_steps", blocked
}

nonisolated enum AnalyticsShelfSource: String, AnalyticsToken {
    case drop, stack, folderTile = "folder_tile", peek, fusion, clipboard
}

nonisolated enum AnalyticsShelfAction: String, AnalyticsToken {
    case opened, added, removed, cleared, itemsOpened = "items_opened", draggedOut = "dragged_out"
    case pasted, previewed, revealed, copied
}

nonisolated enum AnalyticsCapsuleAction: String, AnalyticsToken {
    case panelOpened = "panel_opened", saved, resumed, deleted
}

nonisolated enum AnalyticsTrashAction: String, AnalyticsToken {
    case opened, emptied, dropped
}

nonisolated enum AnalyticsDriveAction: String, AnalyticsToken {
    case stackOpened = "stack_opened", openedInFinder = "opened_in_finder", ejected
}

nonisolated enum AnalyticsEjectOutcome: String, AnalyticsToken {
    case ejected, blocked, failed
}

nonisolated enum AnalyticsAppMeltAction: String, AnalyticsToken {
    case setupOpened = "setup_opened", created, restored, minimized, closed, unpaired, layoutChanged = "layout_changed"
}

nonisolated enum AnalyticsPatchBayAction: String, AnalyticsToken {
    case connected, disconnected, ranAutomatically = "ran_automatically", ranManually = "ran_manually"
}

nonisolated enum AnalyticsClipboardMuseumAction: String, AnalyticsToken {
    case opened, restored, removed, cleared, slideshowStarted = "slideshow_started", exported
}


nonisolated enum AnalyticsDiscoveryAction: String, AnalyticsToken {
    case shown, opened, snoozed, dismissed
}

/// Keys the dock handles while it has keyboard focus.
nonisolated enum AnalyticsFocusCommand: String, AnalyticsToken {
    case windowSearch = "window_search", modePicker = "mode_picker", openFiles = "open_files"
    case badgeMemory = "badge_memory", history, navigate, movePin = "move_pin", open, windowPeek = "window_peek", exit
}

nonisolated enum AnalyticsFocusSessionAction: String, AnalyticsToken {
    case started, paused, resumed, extended, finished, dismissed
}

nonisolated enum AnalyticsPinAction: String, AnalyticsToken {
    case pin, unpin, reorder
}

nonisolated enum AnalyticsPinKind: String, AnalyticsToken {
    case application, folder, mixed
}

/// Which gesture changed the pins. Never which app.
nonisolated enum AnalyticsPinSource: String, AnalyticsToken {
    case menu, voiceOver = "voice_over", keyboard, drag, launcher, other

    init(_ trigger: AnalyticsTrigger?) {
        switch trigger {
        case .menu: self = .menu
        case .voiceOver: self = .voiceOver
        case .keyboard: self = .keyboard
        case .drag, .springLoad: self = .drag
        case .launcher: self = .launcher
        default: self = .other
        }
    }
}

/// Which settings model a change belongs to.
nonisolated enum AnalyticsSettingArea: String, AnalyticsToken {
    case sharedDock = "shared_dock", display, atmosphere, menuBar = "menu_bar", updates
    /// App-wide feature preferences named by ``AnalyticsFeatureSetting``.
    case features
}

nonisolated enum AnalyticsDisplayRole: String, AnalyticsToken {
    case main, secondary
}

/// A tool window opened from the menu bar or a dock shortcut.
nonisolated enum AnalyticsTool: String, AnalyticsToken {
    case windowSearch = "window_search", localHistory = "local_history", fusion, badgeMemory = "badge_memory"
    case systemSettingsClone = "system_settings_clone", settings
}
