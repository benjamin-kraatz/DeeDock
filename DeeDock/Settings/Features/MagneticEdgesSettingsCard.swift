import SwiftUI

/// App-wide control for pin and stack magnetism while dragging and after release.
///
/// Deprecated. The page stays under Settings → Features → Deprecated. Launch turns
/// `magneticEdges` off. Magnetism is deliberately not per-display: a drag can cross
/// screens, so the setting is read from the shared store even when a display profile
/// is being edited. `locked` dims the switch while another owner (an active mode)
/// controls the value, leaving the explanatory copy readable.
struct MagneticEdgesSettingsCard: View {
    /// Provides the shared settings binding for `magneticEdges`.
    let source: SettingsValueSource
    /// Disables editing without hiding the current state.
    var locked: Bool = false

    var body: some View {
        SettingsCard(title: .settingsMagneticEdges, footnote: .settingsMagneticEdgesHelp) {
            SettingsToggleRow(
                title: .settingsMagneticEdgesToggle,
                subtitle: .settingsMagneticEdgesSubtitle,
                isOn: source.binding(\.magneticEdges)
            )
            .disabled(locked)
        }
    }
}

#if DEBUG
/// A store with no repository never touches real preferences, so previews stay self-contained.
private func previewSource() -> SettingsValueSource {
    SettingsValueSource(store: DockSettingsStore(repository: nil), context: nil)
}

#Preview("Magnetic edges") {
    MagneticEdgesSettingsCard(source: previewSource())
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Deprecated — German, dark") {
    VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
        DeprecatedFeatureNotice()
        MagneticEdgesSettingsCard(source: previewSource())
    }
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
    .environment(\.locale, Locale(identifier: "de"))
    .preferredColorScheme(.dark)
}

#Preview("Locked — dark") {
    MagneticEdgesSettingsCard(source: previewSource(), locked: true)
        .padding(24)
        .preferredColorScheme(.dark)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
