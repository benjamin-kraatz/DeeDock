import SwiftUI

/// Per-display glass sections. The dock generates them; this page renames, reorders, and moves tiles.
struct IslandsSettingsPane: View {
    let context: SettingsContext
    /// Set when the sidebar is already editing one display. Nil on the shared Dock page.
    var pinnedDisplayID: String?
    @State private var chosenDisplayID: String?

    private var store: DockIslandStore? { context.coordinator?.islands }
    private var displays: [DisplaySnapshot] { context.profiles.displays.filter(\.hostsDock) }

    private var displayID: String? {
        if let pinnedDisplayID { return pinnedDisplayID }
        if let chosenDisplayID, displays.contains(where: { $0.id == chosenDisplayID }) { return chosenDisplayID }
        return displays.first(where: \.isPrimary)?.id ?? displays.first?.id
    }

    var body: some View {
        if let store, let displayID {
            VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                if pinnedDisplayID == nil, displays.count > 1 {
                    SettingsCard {
                        Picker(selection: Binding(get: { displayID }, set: { chosenDisplayID = $0 })) {
                            ForEach(displays) { display in
                                Text(verbatim: display.name).tag(display.id)
                            }
                        } label: {
                            Text(.islandsDisplay)
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, SettingsMetrics.rowInset)
                        .padding(.vertical, SettingsMetrics.rowVerticalInset)
                    }
                }
                IslandsEditorList(store: store, displayID: displayID)
            }
        } else {
            SettingsCard {
                SettingsStatusRow(symbol: "rectangle.split.3x1", tint: .secondary, message: Text(.islandsUnavailable))
            }
        }
    }
}

/// The island list for one display. Previews construct this directly.
struct IslandsEditorList: View {
    let store: DockIslandStore
    let displayID: String

    private var islands: [DockIslandEditorIsland] { store.editorIslands(for: displayID) }

    var body: some View {
        let islands = islands
        let editableCount = islands.filter(\.canEdit).count
        let storedCount = store.isCustomized(displayID) ? store.document(for: displayID).islands.count : editableCount
        SettingsCard(title: .islandsTitle, footnote: store.isCustomized(displayID) ? .islandsResetHelp : .islandsHelp) {
            if islands.isEmpty {
                SettingsStatusRow(symbol: "rectangle.split.3x1", tint: .secondary, message: Text(.islandsUnavailable))
            } else {
                ForEach(Array(islands.enumerated()), id: \.element.id) { index, island in
                    IslandEditorRow(store: store, displayID: displayID, island: island,
                                    canMoveUp: island.canEdit && index > 0,
                                    canMoveDown: island.canEdit && index + 1 < editableCount,
                                    canDelete: island.canEdit && editableCount > 1,
                                    destinations: islands.filter { $0.canEdit && $0.id != island.id })
                }
            }
            SettingsListFooter {
                Button { store.addIsland(displayID: displayID) } label: {
                    Label { Text(.islandsAdd) } icon: { Image(systemName: "plus") }
                }
                .disabled(storedCount >= DockIslandDocument.maximumIslands)
                if store.isCustomized(displayID) {
                    Button { store.reset(displayID: displayID) } label: {
                        Label { Text(.islandsReset) } icon: { Image(systemName: "arrow.counterclockwise") }
                    }
                }
            }
        }
    }
}

/// One section: its name, order, deletion, and the tiles a person can move elsewhere.
private struct IslandEditorRow: View {
    let store: DockIslandStore
    let displayID: String
    let island: DockIslandEditorIsland
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let destinations: [DockIslandEditorIsland]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if island.canEdit {
                    TextField(String(localized: .islandsNameField), text: name)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(store.resolvedTitle(island.title))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if island.canEdit {
                    SettingsMoreMenu {
                        Button { store.moveIsland(displayID: displayID, id: island.id, by: -1) } label: {
                            Text(.actionMoveUp)
                        }
                        .disabled(!canMoveUp)
                        Button { store.moveIsland(displayID: displayID, id: island.id, by: 1) } label: {
                            Text(.actionMoveDown)
                        }
                        .disabled(!canMoveDown)
                        Divider()
                        Button(role: .destructive) { store.deleteIsland(displayID: displayID, id: island.id) } label: {
                            Text(.islandsDelete)
                        }
                        .disabled(!canDelete)
                    }
                }
            }
            if island.members.isEmpty {
                Text(.islandsEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(island.members) { member in
                    HStack(spacing: 8) {
                        Text(verbatim: member.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !destinations.isEmpty {
                            Menu {
                                ForEach(destinations) { destination in
                                    Button {
                                        store.moveMember(displayID: displayID, memberID: member.id, to: destination.id)
                                    } label: {
                                        Text(store.resolvedTitle(destination.title))
                                    }
                                }
                            } label: {
                                Text(.islandsMoveTo)
                            }
                            .fixedSize()
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(store.resolvedTitle(island.title)))
    }

    private var name: Binding<String> {
        Binding {
            store.resolvedTitle(island.title)
        } set: { newValue in
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let automatic = island.accepts.map { String(localized: $0.title) }
            let stored = automatic == cleaned ? "" : String(cleaned.prefix(40))
            store.rename(displayID: displayID, islandID: island.id, to: stored)
        }
    }
}

#if DEBUG
#Preview("Generated islands") {
    let defaults = UserDefaults(suiteName: "IslandsPreview") ?? .standard
    defaults.removePersistentDomain(forName: "IslandsPreview")
    let store = DockIslandStore(defaults: defaults)
    let icon = NSImage(size: NSSize(width: 32, height: 32))
    let pinned = DockItem(reference: DisplayFixturesPreview.app("Safari"), icon: icon, isFavorite: true,
                          isRunning: true, isAvailable: true)
    let running = DockItem(reference: DisplayFixturesPreview.app("Terminal"), icon: icon, isFavorite: false,
                           isRunning: true, isAvailable: true)
    store.remember(displayID: "display.main", slots: [
        .launcher, .app(pinned), .app(running),
        .shelf(ShelfDockItem(count: 1, icon: icon)),
        .trash(TrashDockItem(state: .empty, icon: icon))
    ])
    return IslandsEditorList(store: store, displayID: "display.main")
        .padding(24)
        .frame(width: 560)
}

private enum DisplayFixturesPreview {
    static func app(_ id: String) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: id, url: URL(fileURLWithPath: "/Fixtures/\(id).app"), name: id)
    }
}
#endif
