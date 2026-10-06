import Foundation

extension AnalyticsEvent {
    /// The event name as PostHog stores it.
    var name: String {
        switch self {
        case .settingChanged: "setting_changed"
        case .usageSummary: "usage_summary"
        case .settingsViewed: "settings_viewed"
        case .permissionRequested: "permission_requested"
        case .permissionChanged: "permission_changed"
        case .loginItemChanged: "login_item_changed"
        case .displaysChanged: "displays_changed"
        case .systemDockTuck: "system_dock_tuck"
        case .onboardingStepReached: "onboarding_step_reached"
        case .onboardingStepSkipped: "onboarding_step_skipped"
        case .onboardingFinished: "onboarding_finished"
        case .onboardingCompleted: "onboarding_completed"
        case .stackOpened: "stack_opened"
        case .stackPresentationChanged: "stack_presentation_changed"
        case .stackSorted: "stack_sorted"
        case .stackQuickLook: "stack_quick_look"
        case .stackItemOpened: "stack_item_opened"
        case .stackDrop: "stack_drop"
        case .smartGrouping: "smart_grouping"
        case .peekOpened: "peek_opened"
        case .peekWindowChosen: "peek_window_chosen"
        case .peekWindowAction: "peek_window_action"
        case .markup: "markup"
        case .portalPinned: "portal_pinned"
        case .watchSetupOpened: "watch_setup_opened"
        case .watchStarted: "watch_started"
        case .watchDetected: "watch_detected"
        case .watchEnded: "watch_ended"
        case .portal: "portal"
        case .portalClosed: "portal_closed"
        case .fileHandoff: "file_handoff"
        case .windowSearchActivated: "window_search_activated"
        case .windowSearchClosed: "window_search_closed"
        case .fusion: "fusion"
        case .launcherOpened: "launcher_opened"
        case .launcherSearched: "launcher_searched"
        case .launcherResultActivated: "launcher_result_activated"
        case .launcherSuggestionAccepted: "launcher_suggestion_accepted"
        case .launcherToolOpened: "launcher_tool_opened"
        case .launcherFileAction: "launcher_file_action"
        case .launcherAssistantAsked: "launcher_assistant_asked"
        case .launcherClosed: "launcher_closed"
        case .launcherSuggestionsShown: "launcher_suggestions_shown"
        case .launcherSuggestionFeedback: "launcher_suggestion_feedback"
        case .launcherSuggestionPromptAnswered: "launcher_suggestion_prompt_answered"
        case .modeSwitched: "mode_switched"
        case .modeEdited: "mode_edited"
        case .workspacePrepared: "workspace_prepared"
        case .workspaceRecipeStarted: "workspace_recipe_started"
        case .workspaceRecipeCompleted: "workspace_recipe_completed"
        case .workspaceRecipeCanceled: "workspace_recipe_canceled"
        case .dockModeActivated: "dock_mode_activated"
        case .shelf: "shelf"
        case .capsule: "session_capsule"
        case .trash: "trash"
        case .drive: "drive"
        case .driveEjected: "drive_ejected"
        case .pinChanged: "pin_changed"
        case .appMenuAction: "app_menu_action"
        case .documentsOpened: "documents_opened"
        case .shortcutRun: "shortcut_run"
        case .shortcutTile: "shortcut_tile"
        case .appMelt: "app_melt"
        case .patchBay: "patch_bay"
        case .clipboardMuseum: "clipboard_museum"
        case .clipboardCaptureEnabled: "clipboard_capture_enabled"
        case .discoveryCallout: "discovery_callout"
        case .toolOpened: "tool_opened"
        case .focusDockEntered: "focus_dock_entered"
        case .focusDockCommand: "focus_dock_command"
        case .focusSession: "focus_session"
        case let .update(event, _): event.name
        case .applicationUpdated: "Application updated"
        }
    }

    var properties: AnalyticsProperties {
        switch self {
        case let .settingChanged(change, area, display):
            change.properties.merging(["area": .init(area), "display_role": display.map(AnalyticsValue.init)])
        case let .usageSummary(properties):
            properties
        case let .settingsViewed(section, page, via, display):
            ["section": .init(section), "page": page.map(AnalyticsValue.init), "via": .init(via),
             "display_role": display.map(AnalyticsValue.init)]
        case let .permissionRequested(permission):
            ["permission": .init(permission)]
        case let .permissionChanged(permission, status):
            ["permission": .init(permission), "status": .init(status)]
        case let .loginItemChanged(operation, outcome, status):
            ["operation": .init(operation), "outcome": .init(outcome), "status": .init(status)]
        case let .displaysChanged(connected, disconnected, newProfileCount, displayCount, externalDisplayCount, dockCount):
            ["connected": .init(connected), "disconnected": .init(disconnected), "new_profile_count": .init(newProfileCount),
             "display_count": .init(displayCount), "external_display_count": .init(externalDisplayCount),
             "dock_count": .init(dockCount)]
        case let .systemDockTuck(action, source, outcome, failure, side, dockRestarted, keptCount):
            ["action": .init(action), "source": .init(source), "outcome": .init(outcome),
             "failure": failure.map(AnalyticsValue.init), "side": side.map(AnalyticsValue.init),
             "dock_restarted": .init(dockRestarted), "kept_count": .init(keptCount)]
        case let .onboardingStepReached(step, index):
            ["step": .init(step), "step_index": .init(index)]
        case let .onboardingStepSkipped(step):
            ["step": .init(step)]
        case let .onboardingFinished(lastStep, completed, systemDockHidden):
            ["last_step": .init(lastStep), "completed": .init(completed), "system_dock_hidden": .init(systemDockHidden)]
        case let .stackOpened(kind, presentation, sort, trigger):
            ["kind": .init(kind), "presentation": .init(presentation), "sort": .init(sort), "trigger": .init(trigger)]
        case let .stackPresentationChanged(presentation, kind, trigger):
            ["presentation": .init(presentation), "kind": kind.map(AnalyticsValue.init), "trigger": .init(trigger)]
        case let .stackSorted(sort, itemCount):
            ["sort": .init(sort), "item_count": .init(itemCount)]
        case let .stackQuickLook(fileType, trigger):
            ["file_type": fileType.map(AnalyticsValue.init), "trigger": .init(trigger)]
        case let .stackItemOpened(fileType, isFolder, trigger):
            ["file_type": fileType.map(AnalyticsValue.init), "is_folder": .init(isFolder), "trigger": .init(trigger)]
        case let .stackDrop(operation, itemCount, fileType, target, outcome):
            ["operation": .init(operation), "item_count": .init(itemCount),
             "file_type": fileType.map(AnalyticsValue.init), "target": .init(target), "outcome": .init(outcome)]
        case let .smartGrouping(source, result, duration, candidateCount, failure):
            ["source": .init(source), "result": .init(result), "duration": .init(duration),
             "candidate_count": .init(candidateCount), "failure": failure.map(AnalyticsValue.init)]
        case let .peekOpened(trigger, cardCount, totalWindowCount, layout, style, size):
            ["trigger": .init(trigger), "card_count": .init(cardCount), "total_window_count": .init(totalWindowCount),
             "layout": .init(layout), "style": .init(style), "size": .init(size)]
        case let .peekWindowChosen(trigger):
            ["trigger": .init(trigger)]
        case let .peekWindowAction(action, outcome, trigger):
            ["action": .init(action), "outcome": .init(outcome), "trigger": .init(trigger)]
        case let .markup(action, hasMarks):
            ["action": .init(action), "has_marks": hasMarks.map(AnalyticsValue.init)]
        case let .portalPinned(source, outcome):
            ["source": .init(source), "outcome": .init(outcome)]
        case let .watchSetupOpened(trigger):
            ["trigger": .init(trigger)]
        case let .watchStarted(usesPhrase, playsSound, completion, usesPreset, hasRegion):
            ["uses_phrase": .init(usesPhrase), "plays_sound": .init(playsSound), "completion": .init(completion),
             "uses_preset": .init(usesPreset), "has_region": .init(hasRegion)]
        case let .watchDetected(detection, duration, checkCount):
            ["detection": .init(detection), "duration": .init(duration), "check_count": .init(checkCount)]
        case let .watchEnded(end, duration, checkCount):
            ["reason": .init(end), "duration": .init(duration), "check_count": .init(checkCount)]
        case let .portal(action, outcome):
            ["action": .init(action), "outcome": outcome.map(AnalyticsValue.init)]
        case let .portalClosed(duration, frameCount, frozen, cropped):
            ["duration": .init(duration), "frame_count": .init(frameCount), "frozen": .init(frozen),
             "cropped": .init(cropped)]
        case let .fileHandoff(action, fileCount, exactWindow, outcome):
            ["action": .init(action), "file_count": .init(fileCount), "exact_window": .init(exactWindow),
             "outcome": .init(outcome)]
        case let .windowSearchActivated(evidence, scope, queryLength, resultCount, outcome):
            ["evidence": .init(evidence), "scope": .init(scope), "query_length": .init(queryLength),
             "result_count": .init(resultCount), "outcome": .init(outcome)]
        case let .windowSearchClosed(scope, queryLength, resultCount, activated, duration):
            ["scope": .init(scope), "query_length": .init(queryLength), "result_count": .init(resultCount),
             "activated": .init(activated), "duration": .init(duration)]
        case let .fusion(step, outcome, failure, operation, duration):
            ["step": .init(step), "outcome": .init(outcome), "failure": failure.map(AnalyticsValue.init),
             "operation": operation.map(AnalyticsValue.init), "duration": .init(duration)]
        case let .launcherOpened(source, fileCount, style):
            ["source": .init(source), "file_count": .init(fileCount), "style": .init(style)]
        case let .launcherSearched(queryLength, resultCount, kind):
            ["query_length": .init(queryLength), "result_count": .init(resultCount), "kind": .init(kind)]
        case let .launcherResultActivated(kind, reveal, trigger):
            ["kind": .init(kind), "reveal": .init(reveal), "trigger": .init(trigger)]
        case let .launcherSuggestionAccepted(trigger):
            ["trigger": .init(trigger)]
        case let .launcherToolOpened(tool):
            ["tool": .init(tool)]
        case let .launcherFileAction(kind, inputCount, source, fileType, status):
            ["action": .init(kind), "input_count": .init(inputCount), "source": .init(source),
             "file_type": fileType.map(AnalyticsValue.init), "status": .init(status)]
        case let .launcherAssistantAsked(queryLength, resultCount, outcome):
            ["query_length": .init(queryLength), "result_count": .init(resultCount), "outcome": .init(outcome)]
        case let .launcherClosed(duration, hadQuery):
            ["duration": .init(duration), "had_query": .init(hadQuery)]
        case let .launcherSuggestionsShown(count):
            ["count": .init(count)]
        case let .launcherSuggestionFeedback(feedback):
            ["feedback": .init(feedback)]
        case let .launcherSuggestionPromptAnswered(answer):
            ["answer": .init(answer)]
        case let .modeSwitched(source, modeCount):
            ["source": .init(source), "mode_count": .init(modeCount)]
        case let .modeEdited(edit, modeCount, stepCount):
            ["action": .init(edit), "mode_count": .init(modeCount), "step_count": stepCount.map(AnalyticsValue.init)]
        case let .workspacePrepared(stepCount, completedStepCount, outcome, duration):
            ["step_count": .init(stepCount), "completed_step_count": .init(completedStepCount),
             "outcome": .init(outcome), "duration": .init(duration)]
        case let .shelf(action, itemCount, source, trigger):
            ["action": .init(action), "item_count": .init(itemCount), "source": source.map(AnalyticsValue.init),
             "trigger": .init(trigger)]
        case let .capsule(action, windowCount, capsuleCount, trigger):
            ["action": .init(action), "window_count": windowCount.map(AnalyticsValue.init),
             "capsule_count": .init(capsuleCount), "trigger": .init(trigger)]
        case let .trash(action, itemCount, outcome, trigger):
            ["action": .init(action), "item_count": itemCount.map(AnalyticsValue.init), "outcome": .init(outcome),
             "trigger": .init(trigger)]
        case let .drive(action, kind, trigger):
            ["action": .init(action), "kind": .init(kind), "trigger": .init(trigger)]
        case let .driveEjected(kind, outcome, forced, blockerCount, trigger):
            ["kind": .init(kind), "outcome": .init(outcome), "forced": .init(forced),
             "blocker_count": .init(blockerCount), "trigger": .init(trigger)]
        case let .pinChanged(action, kind, count, source):
            ["action": .init(action), "kind": .init(kind), "count": .init(count), "source": .init(source)]
        case let .appMenuAction(action, outcome, trigger):
            ["action": .init(action), "outcome": .init(outcome), "trigger": .init(trigger)]
        case let .documentsOpened(source, fileCount, fileType, outcome):
            ["source": .init(source), "file_count": .init(fileCount), "file_type": fileType.map(AnalyticsValue.init),
             "outcome": .init(outcome)]
        case let .shortcutRun(source, fileCount, outcome, duration):
            ["source": .init(source), "file_count": .init(fileCount), "outcome": .init(outcome),
             "duration": .init(duration)]
        case let .shortcutTile(action, tileCount):
            ["action": .init(action), "tile_count": .init(tileCount)]
        case let .appMelt(action, pairCount, outcome):
            ["action": .init(action), "pair_count": .init(pairCount), "outcome": .init(outcome)]
        case let .patchBay(action, cableCount, outcome):
            ["action": .init(action), "cable_count": .init(cableCount), "outcome": outcome.map(AnalyticsValue.init)]
        case let .clipboardMuseum(action, kind, itemCount):
            ["action": .init(action), "kind": kind.map(AnalyticsValue.init), "item_count": itemCount.map(AnalyticsValue.init)]
        case let .discoveryCallout(destination, action):
            ["callout": .init(destination), "action": .init(action)]
        case let .toolOpened(tool, trigger):
            ["tool": .init(tool), "trigger": .init(trigger)]
        case .onboardingCompleted, .workspaceRecipeStarted, .workspaceRecipeCompleted, .workspaceRecipeCanceled,
             .dockModeActivated, .clipboardCaptureEnabled:
            [:]
        case let .focusDockEntered(trigger):
            ["trigger": .init(trigger)]
        case let .focusDockCommand(command):
            ["command": .init(command)]
        case let .focusSession(action):
            ["action": .init(action)]
        case let .update(event, facts):
            facts.properties.merging(event.properties)
        case let .applicationUpdated(change):
            ["previous_version": AnalyticsVersion(change.previous.version).map(AnalyticsValue.init),
             "version": AnalyticsVersion(change.current.version).map(AnalyticsValue.init),
             "previous_build": AnalyticsVersion.build(change.previous.build).map(AnalyticsValue.init),
             "build": AnalyticsVersion.build(change.current.build).map(AnalyticsValue.init),
             "update_source": change.updateSource.map(AnalyticsValue.init),
             "channel": change.channel.map(AnalyticsValue.init)]
        }
    }

    var record: AnalyticsRecord { AnalyticsRecord(name: name, properties: properties) }
}
