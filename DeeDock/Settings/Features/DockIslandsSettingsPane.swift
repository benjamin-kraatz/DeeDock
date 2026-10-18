import SwiftUI

/// Settings → Features → DOKK Islands: the dock-wide island look, then one card per connected
/// display listing its islands for renaming, tinting, splitting, and merging.
struct DockIslandsSettingsPane: View {
    let source: SettingsValueSource
    let profiles: DisplayProfilesStore
    /// Nil in previews and before the coordinator exists; the per-display cards then stay hidden.
    var plans: DockIslandPlanStore?
    var locked = false

    private var settings: DockIslandSettings { source.value.islands }

    var body: some View {
        SettingsCard(title: .islandsTitle, footnote: .islandsEnableHelp) {
            SettingsToggleRow(title: .islandsEnable, subtitle: .islandsEnableSubtitle, isOn: source.binding(\.islands.isEnabled))
        }
        .disabled(locked)
        SettingsCard(title: .islandsLookTitle, footnote: .islandsLookHelp) {
            SettingsMenuRow(title: .islandsStyle, selection: source.binding(\.islands.style)) {
                ForEach(DockIslandStyle.allCases, id: \.self) { style in Text(style.title).tag(style) }
            }
            SettingsMenuRow(title: .islandsTintMode, subtitle: .islandsTintModeHelp, selection: source.binding(\.islands.tintMode)) {
                ForEach(DockIslandTintMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }
            SettingsSliderRow(title: .islandsTintStrength, unit: .settingsMultiplier,
                              value: source.binding(\.islands.tintStrength), range: 0...1.5, step: 0.05,
                              minimumSymbol: "circle", maximumSymbol: "circle.fill",
                              defaultValue: DockIslandSettings.defaults.tintStrength)
            SettingsSliderRow(title: .islandsGlow, unit: .settingsMultiplier,
                              value: source.binding(\.islands.glow), range: 0...2, step: 0.05,
                              minimumSymbol: "sun.min", maximumSymbol: "sun.max.fill",
                              defaultValue: DockIslandSettings.defaults.glow)
            SettingsSliderRow(title: .islandsGap, unit: .settingsPoints,
                              value: source.binding(\.islands.gap), range: 4...48, step: 1,
                              minimumSymbol: "arrow.right.and.line.vertical.and.arrow.left",
                              maximumSymbol: "arrow.left.and.line.vertical.and.arrow.right",
                              defaultValue: DockIslandSettings.defaults.gap)
            SettingsSliderRow(title: .islandsPadding, unit: .settingsPoints,
                              value: source.binding(\.islands.padding), range: 4...28, step: 1,
                              minimumSymbol: "square", maximumSymbol: "square.dashed",
                              defaultValue: DockIslandSettings.defaults.padding)
            SettingsSliderRow(title: .islandsRim, unit: .settingsPoints,
                              value: source.binding(\.islands.rim), range: 0...8, step: 0.5,
                              minimumSymbol: "square", maximumSymbol: "square.inset.filled",
                              defaultValue: DockIslandSettings.defaults.rim)
                .disabled(settings.style != .ice)
        }
        .disabled(locked || !settings.isEnabled)
        if let plans {
            ForEach(profiles.displays.filter(\.hostsDock)) { display in
                DockIslandListCard(display: display, plans: plans,
                                   pins: profiles.pinLists[display.id] ?? [],
                                   tintMode: settings.tintMode)
                    .disabled(locked || !settings.isEnabled)
            }
        }
    }
}

/// One display's islands in dock order, with the pin names each holds.
struct DockIslandListCard: View {
    let display: DisplaySnapshot
    let plans: DockIslandPlanStore
    let pins: [DockPin]
    let tintMode: DockIslandTintMode

    private var plan: DockIslandPlan { plans.plan(for: display.id).reconciled(pinCount: pins.count) }

    /// Pinned islands first, in dock order, then the automatic kind islands.
    private var rows: [DockIslandRowModel] {
        var start = 0
        let pinned = plan.pinnedIslands.enumerated().map { index, island -> DockIslandRowModel in
            let names = pins[start..<min(pins.count, start + island.pinCount)].map(\.name)
            defer { start += island.pinCount }
            let customIndex = plan.pinnedIslands.prefix(index).filter { $0.kind == .custom }.count
            return DockIslandRowModel(island: island, names: Array(names), pinnedIndex: index,
                                      firstPin: start, color: swatch(for: island, customIndex: customIndex))
        }
        return [row(kind: .tile)] + pinned + [row(kind: .running), row(kind: .utilities)]
    }

    private func row(kind: DockIslandKind) -> DockIslandRowModel {
        let island = plan.island(for: kind)
        return DockIslandRowModel(island: island, names: [], pinnedIndex: nil, firstPin: 0, color: swatch(for: island))
    }

    /// The row's swatch: the island's own tint, else what the dock-wide colour source would give it.
    /// Icon-derived colours need the live icons, so that mode previews the kind palette here.
    private func swatch(for island: DockIsland, customIndex: Int = 0) -> DockIslandColor {
        if let own = DockIslandPalette.color(for: island.tint) { return own }
        switch tintMode {
        case .accent: return .accent
        case .none: return .untinted
        case .byKind, .fromIcons: return DockIslandPalette.color(for: island.kind, customIndex: customIndex)
        }
    }

    var body: some View {
        let rows = rows
        SettingsCard(title: .islandsListTitle(display.name), footnote: .islandsListHelp) {
            ForEach(rows) { row in
                DockIslandRow(row: row, pinCount: pins.count, plan: plan, tintMode: tintMode,
                              rename: { name in save(plan.updating(row.island.kind, id: row.island.id) { $0.name = name }, .rename) },
                              tint: { tint in save(plan.updating(row.island.kind, id: row.island.id) { $0.tint = tint }, .tint) },
                              split: { pinIndex in save(plan.splitting(beforePin: pinIndex, pinCount: pins.count), .split) },
                              merge: { direction in
                                  guard let index = row.pinnedIndex else { return }
                                  save(plan.merging(islandAt: index, into: direction, pinCount: pins.count), .merge)
                              })
            }
            SettingsListFooter {
                Button(role: .destructive) { save(.automatic, .reset) } label: { Text(.islandsReset) }
                    .disabled(plan.isAutomatic)
            }
        }
    }

    private func save(_ proposed: DockIslandPlan, _ action: AnalyticsIslandAction) {
        guard proposed != plan else { return }
        withAnimation(.snappy(duration: 0.25)) {
            if plans.save(proposed, for: display.id) {
                Analytics.track(.islandsEdited(action, islandCount: proposed.reconciled(pinCount: pins.count).pinnedIslands.count))
            }
        }
    }
}

/// What one island row shows.
struct DockIslandRowModel: Identifiable {
    let island: DockIsland
    /// Names of the pins inside, empty for kind islands. Shown only on this Mac.
    let names: [String]
    /// Position among the pinned islands, or nil for a kind island.
    let pinnedIndex: Int?
    /// Pin index of the island's first pin.
    let firstPin: Int
    let color: DockIslandColor
    var id: UUID { island.id }
}

/// Swatch, editable name, pin names, and the row's menu of island actions.
private struct DockIslandRow: View {
    let row: DockIslandRowModel
    let pinCount: Int
    let plan: DockIslandPlan
    let tintMode: DockIslandTintMode
    let rename: (String?) -> Void
    let tint: (DockIslandTint) -> Void
    let split: (Int) -> Void
    let merge: (Int) -> Void
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var canMergeBefore: Bool { (row.pinnedIndex ?? 0) > 0 }
    private var canMergeAfter: Bool {
        guard let index = row.pinnedIndex else { return false }
        return index < plan.pinnedIslands.count - 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(row.color.color(brightness: 0.8))
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                TextField(text: $draft, prompt: Text(row.island.kind.defaultName)) { Text(.islandsName) }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .focused($editing)
                    .onSubmit { commit() }
                    .onChange(of: editing) { _, focused in if !focused { commit() } }
                    .onAppear { draft = row.island.name ?? "" }
                    .onChange(of: row.island.name) { _, name in if !editing { draft = name ?? "" } }
                    .accessibilityLabel(Text(.islandsName))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(selection: Binding(get: { row.island.tint }, set: { tint($0) })) {
                ForEach(DockIslandTint.allCases, id: \.self) { value in Text(value.title).tag(value) }
            } label: { Text(.islandsTint) }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(Text(.islandsTint))
            if row.pinnedIndex != nil {
                SettingsMoreMenu {
                    Menu { splitItems } label: { Text(.islandsSplitBefore) }
                        .disabled(row.names.count < 2)
                    Button { merge(-1) } label: { Text(.islandsMergePrevious) }.disabled(!canMergeBefore)
                    Button { merge(1) } label: { Text(.islandsMergeNext) }.disabled(!canMergeAfter)
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
    }

    /// Every pin but the first can start a new island.
    @ViewBuilder private var splitItems: some View {
        ForEach(Array(row.names.enumerated().dropFirst()), id: \.offset) { offset, name in
            Button { split(row.firstPin + offset) } label: { Text(verbatim: name) }
        }
    }

    private var subtitle: String {
        if row.pinnedIndex != nil {
            return row.names.isEmpty ? String(localized: .islandsNoPins) : row.names.joined(separator: " · ")
        }
        return String(localized: row.island.kind.defaultName) + " · " + String(localized: .islandsAutomaticKind)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (row.island.name ?? "") else { return }
        rename(trimmed.isEmpty ? nil : trimmed)
    }
}

private extension DockIslandPlan {
    /// Routes an edit to a pinned island by ID or to a kind island by kind.
    func updating(_ kind: DockIslandKind, id: UUID, mutation: (inout DockIsland) -> Void) -> DockIslandPlan {
        kind.holdsPins ? updating(id, mutation: mutation) : updating(kind: kind, mutation: mutation)
    }
}

#if DEBUG
    #Preview("Islands list") {
        let plans = DockIslandPlanStore(defaults: UserDefaults(suiteName: "preview.islands")!)
        let display = DisplaySnapshot(id: "preview", runtimeID: 1, name: "Built-in Display", isPersistent: true, isPrimary: true,
                                      frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875), mirrorSource: nil, isDrawable: true)
        let pins = ["Mail", "Messages", "Xcode", "Terminal", "Slack"].map {
            DockPin.application(ApplicationReference(bundleIdentifier: "preview.\($0.lowercased())",
                                                     url: URL(fileURLWithPath: "/Applications/\($0).app"), name: $0))
        }
        let _ = plans.save(DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 3),
                                                          DockIsland(kind: .custom, name: "Chat", tint: .pink, pinCount: 2)]),
                           for: display.id)
        ScrollView {
            DockIslandListCard(display: display, plans: plans, pins: pins, tintMode: .byKind)
                .padding(24)
        }
        .frame(width: SettingsMetrics.columnWidth, height: 520)
    }
#endif
