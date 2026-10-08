import Foundation

/// Everything DOKK reports about how it is used.
///
/// Each case carries only enums, Bools, exact numbers, and DOKK's own version numbers
/// (``AnalyticsVersion``). There is no case that takes free text, which is what keeps app
/// names, bundle IDs, paths, window titles, queries, and user-entered names out by construction. `docs/ANALYTICS.md` lists every event with its properties and must
/// be updated together with this enum.
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

    // Launcher
    /// `style` is the Launcher that actually opened: a file drop opens the full one even when the
    /// dock's setting is compact.
    case launcherOpened(AnalyticsLauncherSource, fileCount: Int, style: LauncherStyle)
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
    case discoveryCallout(DiscoveryProposal.Destination, action: AnalyticsDiscoveryAction)
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
