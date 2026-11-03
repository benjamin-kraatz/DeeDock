import SwiftUI

/// The menu-bar command that opens Harbor. It shows a global shortcut only while DOKK holds it,
/// so the hint never names a combination that another app answers.
///
/// A menu item shows one shortcut. Shift-Command-Space leads, because it is the one Harbor took
/// over from Find a Window; when another app holds it, the item shows Option-Shift-Command-Space.
struct HarborMenuButton: View {
    let harbor: HarborCoordinator
    let action: () -> Void

    var body: some View {
        if harbor.heldShortcuts.contains(.alternate) {
            Button(.harborShow, action: action)
                .keyboardShortcut(.space, modifiers: [.shift, .command])
        } else if harbor.heldShortcuts.contains(.primary) {
            Button(.harborShow, action: action)
                .keyboardShortcut(.space, modifiers: [.option, .shift, .command])
        } else {
            Button(.harborShow, action: action)
        }
    }
}
