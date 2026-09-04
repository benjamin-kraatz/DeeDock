import SwiftUI

/// Explicit shortcut discovery and pin management; previews never enumerate real shortcuts.
struct ActionTilesSettingsCard: View {
    let controller: ActionTilesController
    @State private var confirmsReset = false

    var body: some View {
        SettingsCard(title: .actionsTitle, footnote: .actionsHelp) {
            SettingsStackedRow {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                        HStack {
                            Image(systemName: "bolt.square.fill").foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(verbatim: tile.name)
                                Text(verbatim: (controller.statuses[tile.id] ?? .idle).title)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Spacer()
                            if controller.statuses[tile.id]?.busy == true {
                                Button(.actionCancel) { controller.cancel(tile.id) }
                            } else {
                                Button(.actionsRun) { controller.run(tile.id) }
                            }
                            Button(.dockModesMoveUp, systemImage: "arrow.up") { controller.move(tile.id, by: -1) }
                                .labelStyle(.iconOnly).disabled(index == 0 || controller.requiresReset)
                            Button(.dockModesMoveDown, systemImage: "arrow.down") { controller.move(tile.id, by: 1) }
                                .labelStyle(.iconOnly).disabled(index == controller.tiles.count - 1 || controller.requiresReset)
                            Button(.actionUnpin) { controller.unpin(tile.id) }
                                .disabled(controller.statuses[tile.id]?.busy == true || controller.requiresReset)
                        }
                    }
                    if let error = controller.error {
                        Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack {
                        Button(.actionsLoad, systemImage: "arrow.clockwise") { controller.refresh() }
                            .disabled(controller.loading)
                        if controller.loading { ProgressView().controlSize(.small) }
                        Menu(.actionsPin) {
                            ForEach(controller.available) { tile in
                                Button(tile.name) { controller.pin(tile) }
                                    .disabled(controller.tiles.contains { $0.id == tile.id })
                            }
                        }
                        .disabled(controller.available.isEmpty || controller.requiresReset || controller.tiles.count >= 30)
                    }
                    if controller.requiresReset {
                        Button(.actionsReset, role: .destructive) { confirmsReset = true }
                    }
                }
            }
        }
        .confirmationDialog(.actionsReset, isPresented: $confirmsReset) {
            Button(.actionsReset, role: .destructive) { controller.reset() }
        } message: { Text(.actionsResetHelp) }
    }
}

#if DEBUG
#Preview("Action Tiles, empty") {
    ActionTilesSettingsCard(controller: ActionTilesController(defaults: UserDefaults(suiteName: "ActionTilesPreview")!))
        .padding().frame(width: 640)
}
#endif
