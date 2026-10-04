#if DEBUG
import SwiftUI

/// Debug-only menu that mimics update states without Sparkle, a download, or a relaunch.
/// Labels are developer copy and stay out of the string catalog.
struct UpdateDebugMenu: View {
    let updater: AppUpdater

    var body: some View {
        Menu {
            Button { updater.debugSimulateDownload() } label: {
                Text(verbatim: "Silent download ready (badge + pip, callout held)")
            }
            Button { updater.debugSimulateDownload(calloutDue: true) } label: {
                Text(verbatim: "Silent download ready, callout due")
            }
            Button { updater.debugSimulateDownload(idleAfter: 15) } label: {
                Text(verbatim: "Silent download, idle install after 15 s without dock use")
            }
            Button { updater.debugSimulateAvailable() } label: {
                Text(verbatim: "Offer that needs you (callout button runs a real check)")
            }
            Divider()
            Button { updater.debugSimulateInstalled() } label: {
                Text(verbatim: "Just auto-installed (callout, pip, menu notice)")
            }
            Divider()
            Button { updater.debugReset() } label: { Text(verbatim: "Reset") }
        } label: {
            Text(verbatim: "Debug: Simulate Update")
        }
    }
}
#endif
