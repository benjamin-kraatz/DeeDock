import SwiftUI

/// Pin management with discovery on appear; previews never enumerate real shortcuts.
struct ActionTilesSettingsCard: View {
    let controller: ActionTilesController
    @State private var confirmsReset = false

    var body: some View {
        SettingsCard(title: .actionsTitle, footnote: .actionsHelp) {
            ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                HStack(spacing: 11) {
                    SettingsIconTile(glyph: .symbol("bolt.fill"), colors: SettingsPage.actionTiles.tileColors, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: tile.name).lineLimit(1)
                        Text(verbatim: (controller.statuses[tile.id] ?? .idle).title)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: SettingsMetrics.controlSpacing)
                    if controller.statuses[tile.id]?.busy == true {
                        Button(.actionCancel) { controller.cancel(tile.id) }
                    } else {
                        Button(.actionsRun) { controller.run(tile.id) }
                    }
                    SettingsMoreMenu {
                        Toggle(isOn: Binding(get: { tile.acceptsFiles },
                                             set: { controller.setAcceptsFiles(tile.id, $0) })) {
                            Text(.launcherFileAcceptsFiles)
                        }
                        .disabled(controller.requiresReset)
                        Divider()
                        Button(.dockModesMoveUp) { controller.move(tile.id, by: -1) }
                            .disabled(index == 0 || controller.requiresReset)
                        Button(.dockModesMoveDown) { controller.move(tile.id, by: 1) }
                            .disabled(index == controller.tiles.count - 1 || controller.requiresReset)
                        Divider()
                        Button(.actionUnpin, role: .destructive) { controller.unpin(tile.id) }
                            .disabled(controller.statuses[tile.id]?.busy == true || controller.requiresReset)
                    }
                }
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.vertical, SettingsMetrics.rowVerticalInset)
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
            }
            if let error = controller.error {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  message: Text(verbatim: error))
                    .textSelection(.enabled)
            }
            SettingsListFooter {
                Menu {
                    ForEach(controller.available) { tile in
                        Button(tile.name) { controller.pin(tile) }
                            .disabled(controller.tiles.contains { $0.id == tile.id })
                    }
                } label: {
                    Label(.actionsPin, systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(controller.available.isEmpty || controller.requiresReset || controller.tiles.count >= 30)
                Button(.actionsLoad, systemImage: "arrow.clockwise") { controller.refresh() }
                    .disabled(controller.loading)
                if controller.loading { ProgressView().controlSize(.small) }
            }
            if controller.requiresReset {
                SettingsActionRow {
                    Button(.actionsReset, role: .destructive) { confirmsReset = true }
                }
            }
        }
        .onAppear { controller.ensureLoaded() }
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
