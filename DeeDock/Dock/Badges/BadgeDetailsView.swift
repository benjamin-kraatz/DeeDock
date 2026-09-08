import SwiftUI

/// One app's badge state: what is observed now, what it was compared against, and what changed.
///
/// The panel never claims delivery of messages. Every value here is an observation of the badge the
/// app draws, and the comparison is against a value the user explicitly marked as checked.
struct BadgeDetailsView: View {
    let memory: BadgeMemoryStore
    let path: String
    let activate: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsDelete = false

    private var current: BadgeObservation { memory.current[path] ?? .unknown }
    private var app: BadgeAppMemory? { memory.document.apps[path] }
    private var tint: Color { BadgeAppArtwork.tint(path, dark: colorScheme == .dark) ?? .accentColor }
    /// A new app can only be tracked while the bounded set has room for it.
    private var canMarkChecked: Bool {
        current != .unknown && !memory.requiresReset && (app != nil || memory.document.apps.count < 100)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                tiles
                actions
                history
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .confirmationDialog(.badgeMemoryDeleteApp, isPresented: $confirmsDelete) {
            Button(.badgeMemoryDeleteApp, role: .destructive) { memory.clearApp(path) }
        } message: { Text(.badgeMemoryDeleteAppHelp) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: BadgeAppArtwork.icon(path))
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: badgeAppName(path))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Menu {
                Button(.badgeMemoryDeleteApp, systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    .disabled(memory.requiresReset)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(.badgeMemoryDeleteApp))
        }
    }

    private var tiles: some View {
        // Three readings of the same badge. ViewThatFits keeps them side by side until the pane is
        // too narrow, which happens well before the window reaches its minimum width.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) { tileContent }
            VStack(alignment: .leading, spacing: 10) { tileContent }
        }
    }

    @ViewBuilder private var tileContent: some View {
        BadgeStatTile(label: .badgeMemoryCurrent, tint: tint) {
            BadgeValueChip(value: current, prominent: true)
        }
        BadgeStatTile(label: .badgeMemoryBaseline, tint: tint,
                      footnote: app?.checked.map { Text($0.date, format: .dateTime.month().day().hour().minute()) }) {
            if let checked = app?.checked {
                BadgeValueChip(value: checked.value, prominent: true)
            } else {
                Text(.badgeMemoryNoBaseline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        BadgeStatTile(label: .badgeMemoryDeltaLabel, tint: tint) {
            if let checked = app?.checked {
                BadgeDeltaChip(delta: current.delta(from: checked.value))
                    .font(.title3)
            } else {
                Text(.badgeMemoryNoDelta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(.badgeMemoryMarkChecked, systemImage: "checkmark.circle") { memory.markChecked(path) }
                .buttonStyle(.borderedProminent)
                .disabled(!canMarkChecked)
            Button(.badgeMemoryResetBaseline, systemImage: "arrow.counterclockwise") { memory.resetBaseline(path) }
                .disabled(app?.checked == nil || memory.requiresReset)
            Spacer(minLength: 0)
            Button(.badgeMemoryOpenApp, systemImage: "arrow.up.forward.app", action: activate)
        }
        .controlSize(.large)
        .tint(tint)
    }

    @ViewBuilder private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.badgeMemoryRecent)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let changes = app?.changes, !changes.isEmpty {
                VStack(spacing: 0) {
                    // Newest first: the last thing observed is what the user is checking against.
                    ForEach(Array(changes.reversed().enumerated()), id: \.element.id) { index, change in
                        if index > 0 { Divider() }
                        HStack {
                            Text(change.date, format: .dateTime.month().day().hour().minute().second())
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer(minLength: 8)
                            BadgeValueChip(value: change.value)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
            } else {
                Text(.badgeMemoryHistoryEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
            }
        }
    }
}

/// One labelled reading inside the details pane.
struct BadgeStatTile<Content: View>: View {
    let label: LocalizedStringResource
    let tint: Color
    var footnote: Text? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            content
            if let footnote {
                footnote
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.14), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
@MainActor private func badgeDetailsPreviewStore() -> BadgeMemoryStore {
    BadgeMemoryStore(defaults: UserDefaults(suiteName: "BadgeDetailsPreview")!)
}

#Preview("No baseline yet") {
    BadgeDetailsView(memory: badgeDetailsPreviewStore(), path: "/Applications/Mail.app", activate: {})
        .frame(width: 520, height: 560)
}

#Preview("No baseline, German") {
    BadgeDetailsView(memory: badgeDetailsPreviewStore(), path: "/Applications/Mail.app", activate: {})
        .environment(\.locale, Locale(identifier: "de"))
        .frame(width: 520, height: 560)
}
#endif
