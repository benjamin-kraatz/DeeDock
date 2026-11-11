import SwiftUI

/// The menu bar extra's "Vapor" item, checked while Vapor is on. It is Vapor's only switch:
/// there is no keyboard shortcut and no Dock tile item.
struct VaporMenuToggle: View {
    let vapor: VaporCoordinator

    var body: some View {
        Toggle(isOn: Binding(get: { vapor.isEnabled }, set: { vapor.setEnabled($0) })) {
            Text(.vaporTitle)
        }
    }
}
