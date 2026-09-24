import SwiftUI

/// Settings → Features → Quick Launch keys: the app-wide switch and any shortcut conflicts.
///
/// Turning the switch on registers Carbon hot keys, which needs no permission, so this card never
/// shows a permission flow. A conflict is another app's registration and is reported, not overridden.
struct QuickLaunchSettingsCard: View {
    @Binding var isOn: Bool
    /// One-based slots whose shortcut another app already owns. Empty when all ten registered.
    let unavailableSlots: [Int]
    let locked: Bool
    let retry: () -> Void

    private var conflictList: String {
        ListFormatter.localizedString(byJoining: unavailableSlots.map { "⌃⌥" + QuickLaunchSlots.label(for: $0) })
    }

    var body: some View {
        SettingsCard(title: .quickLaunchTitle, footnote: .quickLaunchHelp) {
            SettingsToggleRow(title: .quickLaunchToggle, subtitle: .quickLaunchToggleSubtitle, isOn: $isOn)
                .disabled(locked)
            if isOn && !unavailableSlots.isEmpty {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  message: Text(.quickLaunchConflict(keys: conflictList))) {
                    Button(.quickLaunchRetry, action: retry)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Quick Launch, off") {
    QuickLaunchSettingsCard(isOn: .constant(false), unavailableSlots: [], locked: false, retry: {})
        .padding(24).frame(width: SettingsMetrics.columnWidth)
}

#Preview("Quick Launch, conflicts") {
    QuickLaunchSettingsCard(isOn: .constant(true), unavailableSlots: [3, 10], locked: false, retry: {})
        .padding(24).frame(width: SettingsMetrics.columnWidth)
        .preferredColorScheme(.dark)
}
#endif
