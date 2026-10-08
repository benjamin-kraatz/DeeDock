import SwiftUI

/// The menu-bar command that opens Harbor. It shows the global shortcut only while DOKK holds it,
/// so the hint never names a combination that another app answers.
struct HarborMenuButton: View {
    let harbor: HarborCoordinator
    let action: () -> Void

    var body: some View {
        if harbor.shortcutAvailable {
            Button(.harborShow, action: action)
                .keyboardShortcut(.space, modifiers: [.option, .shift, .command])
        } else {
            Button(.harborShow, action: action)
        }
    }
}
