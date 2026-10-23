import Foundation

/// Everything DOKK reports about how it is used.
///
/// Each case carries only enums, Bools, exact numbers, and DOKK's own version numbers
/// (``AnalyticsVersion``). There is no case that takes free text, which is what keeps app
/// names, bundle IDs, paths, window titles, queries, and user-entered names out by construction.
/// The one exception is ``lineIconCoverage(_:)``, which names public apps that lack a Line glyph
/// through ``AnalyticsPublicAppIdentifier``. `docs/ANALYTICS.md` lists every event with its
/// properties and must be updated together with this enum.
///
/// `Application Opened`, `Application Installed`, and `Application Backgrounded` are the SDK's.
/// ``applicationUpdated(_:)`` is DOKK's, sent on the launch after a version or build change.
enum AnalyticsEvent {
    // Settings and periodic reporting
    case settingChanged(AnalyticsSettingChange, area: AnalyticsSettingArea, display: AnalyticsDisplayRole?)
    /// Counter totals and per-display counts, sent about once a day and at quit.
    case usageSummary(AnalyticsProperties)
    /// A Settings section or page came on screen. `page` is nil for a section's overview.
    case settingsViewed(AnalyticsSettingsSection, page: SettingsPage?, via: AnalyticsSettingsNavigation,
                        display: AnalyticsDisplayRole?)

    // App, permissions, and displays
    case permissionRequested(AnalyticsPermission)
    /// macOS reported a different status than DOKK last saw while running.
    case permissionChanged(AnalyticsPermission, status: AnalyticsPermissionStatus)
    case loginItemChanged(AnalyticsLoginItemOperation, outcome: AnalyticsOutcome, status: AnalyticsLoginItem)
    /// Displays were connected or disconnected. The counts describe the arrangement afterwards.
    case displaysChanged(connected: Int, disconnected: Int, newProfileCount: Int, displayCount: Int,
                         externalDisplayCount: Int, dockCount: Int)
    /// The macOS Dock switch acted. `side` is where the Dock is afterwards while DOKK's values
    /// are in place; `keptCount` is how many of the person's own changes a restore left alone.
    case systemDockTuck(AnalyticsSystemDockTuckAction, source: AnalyticsSystemDockTuckSource,
                        outcome: AnalyticsOutcome, failure: AnalyticsSystemDockTuckFailure?,
                        side: SystemDockOrientation?, dockRestarted: Bool, keptCount: Int)

    // Onboarding
    case onboardingStepReached(OnboardingStep, index: Int)
    case onboardingStepSkipped(OnboardingStep)
    case onboardingFinished(lastStep: OnboardingStep, completed: Bool, systemDockHidden: Bool)
    case onboardingCompleted

    // Stacks
    case stackOpened(AnalyticsStackKind, presentation: FolderStackPresentation, sort: FolderStackSort,
                     trigger: AnalyticsTrigger)
    case stackPresentationChanged(FolderStackPresentation, kind: AnalyticsStackKind?, trigger: AnalyticsTrigger)
    case stackSorted(FolderStackSort, itemCount: Int)
    case stackQuickLook(fileType: AnalyticsFileType?, trigger: AnalyticsTrigger)
    case stackItemOpened(fileType: AnalyticsFileType?, isFolder: Bool, trigger: AnalyticsTrigger)
    /// Copy Path or Copy Relative Path on a stack child. The path itself is never sent.
    case stackPathCopied(AnalyticsStackKind, relative: Bool, isFolder: Bool, trigger: AnalyticsTrigger)
    case stackDrop(AnalyticsDropOperation, itemCount: Int, fileType: AnalyticsFileType?,
                   target: AnalyticsDropTarget, outcome: AnalyticsOutcome)
    case smartGrouping(AnalyticsSmartGroupingSource, result: AnalyticsSmartGroupingResult, duration: Double,
                       candidateCount: Int, failure: AnalyticsSmartGroupingFailure?)

    // Window Peek, portals, and Watch
    case peekOpened(AnalyticsPeekTrigger, cardCount: Int, totalWindowCount: Int, layout: WindowPeekLayout,
                    style: WindowPeekStyle, size: WindowPeekSize)
    case peekWindowChosen(trigger: AnalyticsTrigger)
    case peekWindowAction(AnalyticsWindowAction, outcome: AnalyticsOutcome, trigger: AnalyticsTrigger)
    case markup(AnalyticsMarkupAction, hasMarks: Bool?)
    case portalPinned(AnalyticsPortalSource, outcome: AnalyticsOutcome)
    case watchSetupOpened(trigger: AnalyticsTrigger)
    case watchStarted(usesPhrase: Bool, playsSound: Bool, completion: AnalyticsWatchCompletion, usesPreset: Bool,
                      hasRegion: Bool)
    case watchDetected(AnalyticsWatchDetection, duration: Double, checkCount: Int)
    case watchEnded(AnalyticsWatchEnd, duration: Double, checkCount: Int)
    case portal(AnalyticsPortalAction, outcome: AnalyticsOutcome?)
    case portalClosed(duration: Double, frameCount: Int, frozen: Bool, cropped: Bool)
    case fileHandoff(AnalyticsFileHandoffAction, fileCount: Int, exactWindow: Bool, outcome: AnalyticsOutcome)

    // Window Search and Fusion
    case windowSearchActivated(AnalyticsWindowSearchEvidence, scope: WindowSearchScope, queryLength: Int,
                               resultCount: Int, outcome: AnalyticsOutcome)
    case windowSearchClosed(scope: WindowSearchScope, queryLength: Int, resultCount: Int, activated: Bool,
                            duration: Double)
    case fusion(AnalyticsFusionStep, outcome: AnalyticsOutcome, failure: AnalyticsFusionFailure?,
                operation: FusionOperation?, duration: Double)

    // Launcher (the Hub's Apps tab). Opening is reported as `hubOpened`.
    case launcherSearched(queryLength: Int, resultCount: Int, kind: LauncherSearchKind)
    case launcherResultActivated(LauncherSearchKind, reveal: Bool, trigger: AnalyticsTrigger)
    case launcherSuggestionAccepted(trigger: AnalyticsTrigger)
    case launcherToolOpened(LauncherTool)
    case launcherFileAction(LauncherFileActionKind, inputCount: Int, source: LauncherFileSource,
                            fileType: AnalyticsFileType?, status: AnalyticsFileOperationStatus)
    case launcherAssistantAsked(queryLength: Int, resultCount: Int, outcome: AnalyticsOutcome)
    /// The Launcher closed. `hadQuery` is whether search text was present at that moment.
    case launcherClosed(duration: Double, hadQuery: Bool)
    case launcherSuggestionsShown(count: Int)
    case launcherSuggestionFeedback(AnalyticsSuggestionFeedback)
    case launcherSuggestionPromptAnswered(AnalyticsSuggestionPromptAnswer)

    // DOKK Hub
    /// The Hub opened. `tab` is the tab it showed first; `detached` is whether it opened as a window.
    case hubOpened(trigger: AnalyticsHubTrigger, tab: HubTab, detached: Bool)
    case hubTabSelected(HubTab, via: AnalyticsHubTabSwitch)
    /// The pin button turned the Hub into a window (`true`) or attached it to the dock again.
    case hubDetachChanged(detached: Bool)
    /// A copy or move in the Files tab ended. Counts only, never names or paths.
    case hubFileTransfer(AnalyticsHubTransferKind, itemCount: Int, crossVolume: Bool,
                         outcome: AnalyticsHubTransferOutcome)
    case hubFilesViewChanged(AnalyticsHubFilesView)
    /// The Files sidebar's Favorites changed. Counts only, never folder names or paths.
    case hubFilesSidebarEdited(AnalyticsHubSidebarAction, method: AnalyticsHubSidebarMethod, itemCount: Int)
    case hubFileSearchResultOpened(scope: AnalyticsHubSearchScope, isFolder: Bool)
    /// A Files search result opened while Lookout was on: a Spotlight name result or a Lookout hit. `rank` is 1-based
    /// within its section (within its group for a search with a picture); `kind` and `match` are nil for a name
    /// result. `query` says whether words or a picture were searched with. Never the query, a name or a path.
    case lookoutResultOpened(section: AnalyticsLookoutSection, rank: Int, kind: AnalyticsLookoutKind?,
                             match: AnalyticsLookoutMatch?, scope: AnalyticsHubSearchScope, isLookup: Bool,
                             query: AnalyticsLookoutQuery)
    /// A search with a picture started. `cold` is true when the picture reader had to load first. Never the picture,
    /// a name or a path.
    case lookoutImageSearch(source: AnalyticsLookoutImageSource, cold: Bool)
    /// A step of Lookout's onboarding came on screen (also when it opens again at a step).
    case lookoutSetupStepViewed(AnalyticsLookoutSetupStep)
    /// Lookout's onboarding applied setup as the first pass started. `estimatedFiles` is the sum of the included
    /// folders' estimates. Counts and a flag only, never names or paths.
    case lookoutSetupCompleted(folderCount: Int, allowedCount: Int, skippedCount: Int, estimatedFiles: Int,
                               indexOnBattery: Bool)
    /// Lookout's onboarding closed before setup, at `lastStep`.
    case lookoutSetupAbandoned(lastStep: AnalyticsLookoutSetupStep)
    /// One run of Lookout's model download ended. `error` is set when it failed.
    case lookoutModelDownload(outcome: AnalyticsLookoutDownloadOutcome, seconds: Int, error: AnalyticsLookoutDownloadError?)
    /// macOS answered Lookout's request to read a folder ("Allow…" in onboarding, "Add folder…" in Settings). Never
    /// the folder.
    case lookoutAccessResult(AnalyticsLookoutAccessOutcome, context: AnalyticsLookoutAccessContext)
    /// A window was brought forward from the Windows tab.
    case hubWindowActivated(minimized: Bool)

    // Dock Modes
    case modeSwitched(AnalyticsModeSource, modeCount: Int)
    case modeEdited(AnalyticsModeEdit, modeCount: Int, stepCount: Int? = nil)
    case workspacePrepared(stepCount: Int, completedStepCount: Int, outcome: AnalyticsRecipeOutcome, duration: Double)
    case workspaceRecipeStarted
    case workspaceRecipeCompleted
    case workspaceRecipeCanceled
    case dockModeActivated

    // Dock extras
    case shelf(AnalyticsShelfAction, itemCount: Int, source: AnalyticsShelfSource?, trigger: AnalyticsTrigger)
    case capsule(AnalyticsCapsuleAction, windowCount: Int?, capsuleCount: Int, trigger: AnalyticsTrigger)
    case trash(AnalyticsTrashAction, itemCount: Int?, outcome: AnalyticsOutcome, trigger: AnalyticsTrigger)
    case drive(AnalyticsDriveAction, kind: VolumeKind, trigger: AnalyticsTrigger)
    case driveEjected(VolumeKind, outcome: AnalyticsEjectOutcome, forced: Bool, blockerCount: Int,
                      trigger: AnalyticsTrigger)
    case pinChanged(AnalyticsPinAction, kind: AnalyticsPinKind, count: Int, source: AnalyticsPinSource)
    /// A display's islands were split, merged, renamed, retinted, or reset. `islandCount` is the
    /// number of pinned islands afterwards.
    case islandsEdited(AnalyticsIslandAction, islandCount: Int)

    // App tiles
    case appMenuAction(AnalyticsAppMenuAction, outcome: AnalyticsOutcome, trigger: AnalyticsTrigger)
    /// Documents were handed to an app from its tile. A cancelled picker reports `canceled`.
    case documentsOpened(AnalyticsDocumentSource, fileCount: Int, fileType: AnalyticsFileType?,
                         outcome: AnalyticsOutcome)
    case shortcutRun(AnalyticsShortcutSource, fileCount: Int, outcome: AnalyticsOutcome, duration: Double)
    case shortcutTile(AnalyticsShortcutTileAction, tileCount: Int)

    // Tools and personality features
    case appMelt(AnalyticsAppMeltAction, pairCount: Int, outcome: AnalyticsOutcome)
    case patchBay(AnalyticsPatchBayAction, cableCount: Int, outcome: AnalyticsOutcome?)
    case clipboardMuseum(AnalyticsClipboardMuseumAction, kind: ClipboardExhibitKind?, itemCount: Int?)
    case clipboardCaptureEnabled
    /// The notification feed opened. Counts only: never notification text or app names.
    case notificationFeedOpened(entryCount: Int, unreadCount: Int, trigger: AnalyticsTrigger)
    /// The notification feed closed, with how many entries it held then.
    case notificationFeedClosed(entryCount: Int, duration: Double, cleared: Bool)
    /// Harbor opened. Counts only: never window titles or app names.
    case harborOpened(trigger: AnalyticsTrigger, windowCount: Int, appCount: Int, displayCount: Int,
                      access: AnalyticsHarborAccess)
    /// Harbor closed, with how it ended and whether search or the app filter was used.
    case harborClosed(outcome: AnalyticsHarborOutcome, duration: Double, searched: Bool, filtered: Bool,
                      closedWindows: Int)
    /// A plugin's panel opened. Counts only: never the plugin, its app, or anything it shows.
    case pluginPanelOpened(trigger: AnalyticsTrigger, pinnedCount: Int)
    /// A plugin's panel closed. `stopped` is true when the plugin had stopped by then.
    case pluginPanelClosed(duration: Double, stopped: Bool)
    /// A plugin's process ended without DOKK asking, such as a crash.
    case pluginStopped(panelOpen: Bool)
    /// A stopped plugin was restarted, and from where.
    case pluginRestarted(surface: AnalyticsPluginSurface)
    /// A plugin tile was pinned or unpinned. Newly approved plugins report `automatic`.
    case pluginPinChanged(pinned: Bool, surface: AnalyticsPluginSurface)
    /// The system's plugin approval window opened from Settings.
    case pluginsManageOpened(waitingCount: Int)
    /// How many plugins are on, waiting, off, and pinned. Sent when the counts change.
    case pluginsCounted(enabledCount: Int, waitingCount: Int, disabledCount: Int, pinnedCount: Int)
    case discoveryCallout(DiscoveryProposal.Destination, action: AnalyticsDiscoveryAction)
    /// How many installed and pinned apps have a Line glyph, with the bundle IDs of public apps
    /// that have none. Sent shortly after launch, at most every six hours.
    case lineIconCoverage(LineIconCoverage)
    case toolOpened(AnalyticsTool, trigger: AnalyticsTrigger)

    // Focus Dock and focus sessions
    case focusDockEntered(trigger: AnalyticsTrigger)
    case focusDockCommand(AnalyticsFocusCommand)
    case focusSession(AnalyticsFocusSessionAction)

    // Updates
    /// One step of the update flow, with the versions, settings, and phase it happened in.
    case update(AnalyticsUpdateEvent, AnalyticsUpdateFacts)
    /// The first launch after the marketing version or the build changed.
    case applicationUpdated(ApplicationUpdateLaunch.Change)
}
