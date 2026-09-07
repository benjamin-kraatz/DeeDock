import SwiftUI

/// Native tabs, disclosure groups and buttons provide keyboard and VoiceOver navigation.
struct BadgeMemoryView: View {
    let memory: BadgeMemoryStore
    @Bindable var presentation: BadgeMemoryPresentation
    let activate: (String) -> Void
    let close: () -> Void
    @State private var confirmsClear = false

    private var paths: [String] {
        Set(memory.document.apps.keys).union(presentation.path.map { [$0] } ?? []).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.badgeMemoryHelp).foregroundStyle(.secondary)
            if memory.storageFailed { Text(.badgeMemoryStorageFailed).foregroundStyle(.red) }
            if presentation.activationFailed { Text(.badgeMemoryActivationFailed).foregroundStyle(.red) }
            TabView(selection: $presentation.tab) {
                Tab(String(localized: .badgeMemoryDetails), systemImage: "app.badge", value: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if paths.isEmpty { Text(.badgeMemoryEmpty) }
                            else {
                                Picker(.badgeMemoryApp, selection: $presentation.path) {
                                    Text(.badgeMemorySelectApp).tag(String?.none)
                                    ForEach(paths, id: \.self) { path in
                                        Text(verbatim: badgeAppName(path)).tag(Optional(path))
                                    }
                                }
                                if let path = presentation.path {
                                    BadgeDetailsView(memory: memory, path: path, activate: { activate(path) })
                                }
                            }
                        }.padding()
                    }
                }
                Tab(String(localized: .badgeMemoryDigest), systemImage: "timer", value: 1) {
                    BadgeDigestView(memory: memory, activate: activate)
                }
            }
            Toggle(.badgeMemoryCollect, isOn: Binding(get: { memory.document.collectFocus }, set: memory.setCollectFocus))
                .disabled(memory.requiresReset)
            Text(.badgeMemoryRetention).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(.badgeMemoryClearAll, role: .destructive) { confirmsClear = true }
                Spacer()
                Button(.badgeMemoryClose, action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(.badgeMemoryClearAll, isPresented: $confirmsClear) {
            Button(.badgeMemoryClearAll, role: .destructive) { memory.clearAll() }
        } message: { Text(.badgeMemoryClearHelp) }
    }
}

/// Filename supplied by the installation, without querying metadata during view rendering.
func badgeAppName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }

struct BadgeValueText: View {
    let value: BadgeObservation
    var body: some View {
        switch value {
        case .unknown: Text(.badgeMemoryUnknown)
        case .cleared: Text(.badgeMemoryCleared)
        case .count(let count): Text(.badgeMemoryCount(Int(count)))
        case .text(let text): Text(.badgeMemoryText(text))
        }
    }
}

struct BadgeDetailsView: View {
    let memory: BadgeMemoryStore
    let path: String
    let activate: () -> Void
    @State private var confirmsDelete = false
    private var current: BadgeObservation { memory.current[path] ?? .unknown }
    private var app: BadgeAppMemory? { memory.document.apps[path] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: badgeAppName(path)).font(.title2)
            Text(verbatim: path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            LabeledContent { BadgeValueText(value: current) } label: { Text(.badgeMemoryCurrent) }
            if let checked = app?.checked {
                LabeledContent { BadgeValueText(value: checked.value) } label: { Text(.badgeMemoryBaseline) }
                Text(checked.date, format: .dateTime.year().month().day().hour().minute())
                if let delta = current.delta(from: checked.value) {
                    Text(.badgeMemoryDelta(delta.formatted(.number.sign(strategy: .always()))))
                } else { Text(.badgeMemoryNoDelta) }
            } else { Text(.badgeMemoryNoBaseline) }
            HStack {
                Button(.badgeMemoryMarkChecked) { memory.markChecked(path) }
                    .disabled(current == .unknown || memory.requiresReset || (app == nil && memory.document.apps.count >= 100))
                Button(.badgeMemoryResetBaseline) { memory.resetBaseline(path) }
                    .disabled(app?.checked == nil || memory.requiresReset)
            }
            HStack {
                Button(.badgeMemoryOpenApp, action: activate)
                Button(.badgeMemoryDeleteApp, role: .destructive) { confirmsDelete = true }
                    .disabled(memory.requiresReset)
            }
            if let changes = app?.changes, !changes.isEmpty {
                Divider()
                Text(.badgeMemoryRecent).font(.headline)
                ForEach(changes.reversed()) { change in
                    HStack {
                        Text(change.date, format: .dateTime.month().day().hour().minute().second())
                        Spacer()
                        BadgeValueText(value: change.value)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .confirmationDialog(.badgeMemoryDeleteApp, isPresented: $confirmsDelete) {
            Button(.badgeMemoryDeleteApp, role: .destructive) { memory.clearApp(path) }
        } message: { Text(.badgeMemoryDeleteAppHelp) }
    }
}

#if DEBUG
#Preview("Known, cleared, text and unknown") {
    VStack(alignment: .leading, spacing: 12) {
        BadgeValueText(value: .count(41))
        BadgeValueText(value: .cleared)
        BadgeValueText(value: .text("99+"))
        BadgeValueText(value: .unknown)
    }.padding()
}
#endif
