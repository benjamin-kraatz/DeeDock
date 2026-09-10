#if DEBUG
import SwiftUI

/// Debug-only controls that move the Sims care clock forward without waiting.
///
/// The card is presentation only: it reports the store's session offset and hands each step back
/// through ``advance``/``reset``. Nothing here is persisted, and the whole file is compiled out of
/// Release, so the offset can never reach `dock.sims.v1`.
struct DockSimsDebugClockCard: View {
    /// Seconds the care clock currently runs ahead of the wall clock.
    let offset: TimeInterval
    /// Moves the care clock forward by the given number of seconds.
    let advance: (TimeInterval) -> Void
    /// Returns the care clock to the wall clock.
    let reset: () -> Void

    /// Formatted with `Duration` so the hour and minute symbols follow the reader's locale
    /// instead of a hard-coded "h". Minutes appear only when the offset is not a whole hour.
    private var formattedOffset: String {
        Duration.seconds(offset.isFinite ? offset : 0)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        SettingsCard(title: .simsDebugTitle, footnote: .simsDebugHelp) {
            SettingsRow(title: .simsDebugOffset) {
                Text(verbatim: formattedOffset)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            SettingsActionRow {
                Button(.simsDebugAdvance1h) { advance(DockSimsLimits.debugHour) }
                Button(.simsDebugAdvance2h) { advance(DockSimsLimits.debugTwoHours) }
                Button(.simsDebugAdvance6h) { advance(DockSimsLimits.debugHungryStep) }
                Button(.simsDebugAdvance8h) { advance(DockSimsLimits.debugLonelyStep) }
            }
            SettingsActionRow {
                Button(.simsDebugResetClock, action: reset)
                    .disabled(offset == 0)
            }
        }
    }
}

#Preview("At wall clock") {
    DockSimsDebugClockCard(offset: 0, advance: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Six hours ahead") {
    DockSimsDebugClockCard(offset: 6 * 3_600, advance: { _ in }, reset: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}
#endif
