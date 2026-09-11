#if DEBUG
import SwiftUI

/// Debug builds only: tunes how often DDock falls back to asking Finder for the Trash count.
/// Release builds always use `TrashRefreshInterval.standard`.
struct TrashRefreshIntervalDebugRow: View {
    @AppStorage(TrashRefreshInterval.defaultsKey) private var interval = TrashRefreshInterval.standard

    var body: some View {
        SettingsSliderRow(title: .settingsTrashRefreshInterval, unit: .settingsSeconds, value: $interval,
                          range: TrashRefreshInterval.range, step: 1,
                          defaultValue: TrashRefreshInterval.standard)
    }
}

#Preview("Trash check interval") {
    SettingsCard(title: .settingsTrash, footnote: .settingsTrashHelp) {
        TrashRefreshIntervalDebugRow()
    }
    .padding(24)
    .frame(width: SettingsMetrics.columnWidth)
}
#endif
