import SwiftUI

/// Keeps recovery actions reachable even when all display docks are disabled.
struct AppMeltMenu: View {
    let controller: AppMeltController
    var body: some View {
        Menu {
            Button(.meltCreate) { controller.showSetup() }
            ForEach(controller.pairs) { pair in
                Menu {
                    if let message = pair.message { Text(message) }
                    Button(.meltRestore) { controller.restore(pair) }.disabled(pair.busy)
                    Button(.meltMinimize) { controller.minimize(pair) }.disabled(pair.busy)
                    Button(.meltClose) { controller.close(pair) }.disabled(pair.busy)
                    Divider()
                    Button(.meltUnpair) { controller.unpair(pair) }
                } label: { Text(verbatim: pair.title) }
            }
        } label: { Text(.meltTitle) }
    }
}
