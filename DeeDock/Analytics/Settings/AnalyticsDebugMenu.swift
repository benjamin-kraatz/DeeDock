#if DEBUG
import SwiftUI

/// Debug-only switch for sending analytics from a development build.
///
/// Debug builds send nothing by default. With the switch on, events go to the same project as
/// release builds, tagged `channel=debug`. The label is developer copy and stays out of the
/// string catalog.
struct AnalyticsDebugMenu: View {
    let analytics: Analytics

    var body: some View {
        Toggle(isOn: Binding(get: { analytics.debugSendingEnabled },
                             set: { analytics.debugSendingEnabled = $0 })) {
            Text(verbatim: "Debug: Send Analytics (channel=debug)")
        }
    }
}
#endif
