import Foundation

/// Everything DOKK reports about how it is used.
///
/// Each case carries only enums, Bools, and exact numbers. There is no case that takes text,
/// which is what keeps app names, bundle IDs, paths, window titles, queries, and user-entered
/// names out by construction. `docs/ANALYTICS.md` lists every event with its properties and must
/// be updated together with this enum.
///
/// Events PostHog captures by itself (app opened, installed, updated) have no case here.
enum AnalyticsEvent {
    // Settings and periodic reporting
    case settingChanged(AnalyticsSettingChange, area: AnalyticsSettingArea, display: AnalyticsDisplayRole?)
    /// Counter totals and per-display counts, sent about once a day and at quit.
    case usageSummary(AnalyticsProperties)

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

    // Launcher
    case launcherOpened(AnalyticsLauncherSource, fileCount: Int)
    case launcherSearched(queryLength: Int, resultCount: Int, kind: LauncherSearchKind)
    case launcherResultActivated(LauncherSearchKind, reveal: Bool, trigger: AnalyticsTrigger)
    case launcherSuggestionAccepted(trigger: AnalyticsTrigger)
    case launcherToolOpened(LauncherTool)
    case launcherFileAction(LauncherFileActionKind, inputCount: Int, source: LauncherFileSource,
                            fileType: AnalyticsFileType?, status: AnalyticsFileOperationStatus)
    case launcherAssistantAsked(queryLength: Int, resultCount: Int, outcome: AnalyticsOutcome)

    // Dock Modes
    case modeSwitched(AnalyticsModeSource, modeCount: Int)
    case modeEdited(AnalyticsModeEdit, modeCount: Int)
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

    // Tools and personality features
    case appMelt(AnalyticsAppMeltAction, pairCount: Int, outcome: AnalyticsOutcome)
    case patchBay(AnalyticsPatchBayAction, cableCount: Int, outcome: AnalyticsOutcome?)
    case clipboardMuseum(AnalyticsClipboardMuseumAction, kind: ClipboardExhibitKind?, itemCount: Int?)
    case clipboardCaptureEnabled
    case discoveryCallout(DiscoveryProposal.Destination, action: AnalyticsDiscoveryAction)
    case toolOpened(AnalyticsTool, trigger: AnalyticsTrigger)

    // Focus Dock and focus sessions
    case focusDockEntered(trigger: AnalyticsTrigger)
    case focusDockCommand(AnalyticsFocusCommand)
    case focusSession(AnalyticsFocusSessionAction)
}
