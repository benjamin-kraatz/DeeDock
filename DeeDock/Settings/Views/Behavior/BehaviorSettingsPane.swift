import SwiftUI

/// Behavior controls share the existing Settings design and save through individual field bindings.
struct BehaviorSettingsPane: View {
    let source: SettingsValueSource
    var previewReduceMotion: Bool? = nil
    var showZone: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            SettingsCard(title: .settingsAppVisibility, footnote: .settingsAppVisibilityHelp) {
                SettingsMenuRow(title: .settingsAppVisibility,
                                subtitle: source.activeModeName.map { .dockModesSavedIn(modeName: $0) },
                                selection: source.appVisibilityBinding()) {
                    ForEach(DockAppVisibility.allCases, id: \.self) { value in Text(value.title).tag(value) }
                }
                .disabled(!source.modeSettingsAvailable)
                .settingsOverride(source.context, field: .appVisibility)
            }
            SettingsCard(title: .settingsTrash, footnote: .settingsTrashHelp) {
                SettingsToggleRow(title: .settingsShowTrash, isOn: source.binding(\.showTrash))
                    .settingsOverride(source.context, field: .showTrash)
                SettingsToggleRow(title: .settingsConfirmBeforeEmptyingTrash,
                                  isOn: source.binding(\.confirmBeforeEmptyingTrash))
                    .settingsOverride(source.context, field: .confirmBeforeEmptyingTrash)
            }
            SettingsCard(title: .settingsBehavior, footnote: .behaviorHelp) {
                SettingsToggleRow(title: .behaviorAutoHide, isOn: source.binding(\.behavior.autoHide))
                    .settingsOverride(source.context, field: .autoHide)
            }
            SettingsCard(title: .behaviorActivationZone,
                         footnote: source.value.edge == .top ? .behaviorTopZoneHelp : .behaviorZoneHelp) {
                SettingsStackedRow {
                    DockZoneDiagram(settings: source.value)
                    if let showZone {
                        Button(.behaviorShowZone, systemImage: "viewfinder", action: showZone)
                            .controlSize(.small)
                    }
                }
                BehaviorActivationControls(source: source)
            }
            SettingsCard(title: .behaviorTiming, footnote: .behaviorTimingHelp) {
                BehaviorTimingControls(source: source)
            }
            SettingsCard(title: .behaviorAnimation, footnote: .behaviorAnimationHelp) {
                SettingsStackedRow {
                    DockAnimationPreview(edge: source.value.edge, style: source.value.behavior.animationStyle,
                                         duration: source.value.behavior.animationDuration,
                                         reduceMotionOverride: previewReduceMotion)
                }
                BehaviorAnimationPicker(edge: source.value.edge, selection: source.binding(\.behavior.animationStyle))
                    .settingsOverride(source.context, field: .animationStyle)
                SettingsSliderRow(title: .behaviorDuration, unit: .settingsSeconds,
                                  value: source.binding(\.behavior.animationDuration), range: 0...1, step: 0.05)
                    .settingsOverride(source.context, field: .animationDuration)
            }
        }
    }
}

#if DEBUG
#Preview("Behavior defaults") {
    ScrollView { BehaviorSettingsPane(source: SettingsValueSource(store: DockSettingsStore(repository: nil), context: nil)).padding(24) }
        .frame(width: 620, height: 750)
}
#Preview("Behavior overrides — reduced motion") {
    let profiles = DisplaySettingsPreview.make()
    ScrollView { BehaviorSettingsPane(source: SettingsValueSource(store: profiles.defaults,
        context: SettingsOverrideContext(profiles: profiles, id: "display.preview2")), previewReduceMotion: true).padding(24) }
        .preferredColorScheme(.dark).frame(width: 620, height: 750)
}
#endif
