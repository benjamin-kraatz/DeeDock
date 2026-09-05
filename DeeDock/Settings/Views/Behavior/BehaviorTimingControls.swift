import SwiftUI

/// Delays use the same exact-value entry and 0.05-second precision as persistence.
struct BehaviorTimingControls: View {
    let source: SettingsValueSource
    var body: some View {
        VStack(spacing: 0) {
            SettingsSliderRow(title: .behaviorRevealDelay, unit: .settingsSeconds,
                              value: source.binding(\.behavior.revealDelay), range: 0...2, step: 0.05,
                              defaultValue: DockSettings.defaults.behavior.revealDelay)
                .settingsOverride(source.context, field: .revealDelay)
            Divider().padding(.leading, SettingsMetrics.rowInset)
            SettingsSliderRow(title: .behaviorHideDelay, unit: .settingsSeconds,
                              value: source.binding(\.behavior.hideDelay), range: 0...5, step: 0.05,
                              defaultValue: DockSettings.defaults.behavior.hideDelay)
                .settingsOverride(source.context, field: .hideDelay)
        }
    }
}
