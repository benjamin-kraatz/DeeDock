import SwiftUI

/// Settings → Flix Files: where it lives, what it tracks, web links, intelligence, and privacy.
///
/// Nothing here asks macOS for access by itself: a watched folder's **Allow…** and **Add Folder…**
/// are the only controls that read a protected folder, and only when pressed.
struct FlixSettingsPane: View {
    let flix: FlixCoordinator
    var robi: RobiStore?

    var body: some View {
        FlixSettingsContent(store: flix.settingsStore, shortcutStatus: flix.shortcutStatus,
                            requestingAccess: flix.requestingAccess, engines: flix.intelligence.engines,
                            historyCount: flix.history.items.count,
                            recordingChanged: { flix.isRecordingShortcut = $0 },
                            requestAccess: { flix.requestAccess($0) },
                            addFolder: { flix.addWatchedFolder($0) },
                            forgetDragMemory: { flix.intelligence.forgetDragMemory() },
                            clearHistory: { flix.history.clear() })
        .task { flix.intelligence.engines = .current(robi: robi) }
    }
}

/// The page over plain values and closures, so previews need no live coordinator.
struct FlixSettingsContent: View {
    @Bindable var store: FlixSettingsStore
    let shortcutStatus: FlixShortcutStatus
    let requestingAccess: String?
    let engines: FlixEngineStatus
    let historyCount: Int
    var recordingChanged: (Bool) -> Void = { _ in }
    var requestAccess: (String) -> Void = { _ in }
    var addFolder: (URL) -> Void = { _ in }
    var forgetDragMemory: () -> Void = {}
    var clearHistory: () -> Void = {}

    var body: some View {
        SettingsPageScaffold {
            SettingsCard(footnote: .flixSettingsFootnote) {
                SettingsToggleRow(title: .flixSettingsEnabled, subtitle: .flixSettingsEnabledHelp,
                                  isOn: $store.settings.isEnabled)
            }
            Group {
                FlixPlacementCard(settings: $store.settings, shortcutStatus: shortcutStatus,
                                  recordingChanged: recordingChanged)
                FlixBehaviorCard(settings: $store.settings)
                FlixTrackingCard(settings: $store.settings)
                FlixWatchedFoldersCard(store: store, requestingAccess: requestingAccess,
                                       requestAccess: requestAccess, addFolder: addFolder)
                FlixWebLinksCard(settings: $store.settings)
                FlixIntelligenceCard(settings: $store.settings, engines: engines, forgetDragMemory: forgetDragMemory)
                FlixHistoryCard(count: historyCount, clear: clearHistory)
            }
            .disabled(!store.settings.isEnabled)
            FlixPrivacyNote()
        }
        .navigationTitle(Text(.flixName))
    }
}

#if DEBUG
#Preview("Flix Files settings") {
    FlixSettingsContent(store: FlixSettingsStore(repository: nil), shortcutStatus: .registered, requestingAccess: nil,
                        engines: FlixEngineStatus(lookout: .ready(detail: 4), appleIntelligence: .ready(detail: nil),
                                                  robi: .ready(detail: nil)),
                        historyCount: 128)
        .frame(width: 700, height: 900)
}

#Preview("Flix Files settings, shortcut taken, German") {
    FlixSettingsContent(store: FlixSettingsStore(repository: nil), shortcutStatus: .unavailable, requestingAccess: nil,
                        engines: FlixEngineStatus(), historyCount: 0)
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 700, height: 900)
}
#endif
