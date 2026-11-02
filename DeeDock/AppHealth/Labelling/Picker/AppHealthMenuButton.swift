import SwiftUI

/// "Something's off right now…" in the menu-bar menu, shown only while labelling is active (collection and
/// labelling both on). Isolated so Observation tracks the controller when the menu refreshes.
struct AppHealthMenuButton: View {
    let controller: AppHealthController
    let action: () -> Void

    var body: some View {
        if controller.isLabellingActive {
            Button(.appHealthSomethingOff, action: action)
        }
    }
}
