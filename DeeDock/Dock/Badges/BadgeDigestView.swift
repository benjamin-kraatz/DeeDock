import SwiftUI

/// What badges did during Focus Sessions, one card per session, newest first.
struct BadgeDigestView: View {
    let memory: BadgeMemoryStore
    let activate: (String) -> Void

    /// An active session leads: it is the one still changing.
    private var digests: [BadgeFocusDigest] {
        (memory.document.active.map { [$0] } ?? []) + memory.document.digests
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(.badgeMemoryDigestHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if digests.isEmpty {
                    ContentUnavailableView {
                        Label(.badgeMemoryDigest, systemImage: "timer")
                    } description: {
                        Text(.badgeMemoryDigestEmpty)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(digests) { digest in
                        BadgeDigestSection(digest: digest, activate: activate,
                                           delete: { memory.deleteDigest(digest.id) })
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One session's card. Rows without an observed change stay out; they would be noise.
private struct BadgeDigestSection: View {
    let digest: BadgeFocusDigest
    let activate: (String) -> Void
    let delete: () -> Void
    @State private var expanded = true
    @State private var confirmsDelete = false

    private var paths: [String] { digest.rows.keys.filter { digest.rows[$0]!.changes > 0 }.sorted() }
    private var collecting: Bool { digest.ended == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if digest.incomplete { gap }
                    if paths.isEmpty {
                        Text(.badgeMemoryNoChanges)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(paths, id: \.self) { path in
                            if let row = digest.rows[path] {
                                BadgeDigestRowView(path: path, row: row) { activate(path) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
        .confirmationDialog(.badgeMemoryDeleteDigest, isPresented: $confirmsDelete) {
            Button(.badgeMemoryDeleteDigest, role: .destructive, action: delete)
        } message: { Text(.badgeMemoryDeleteDigestHelp) }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { expanded.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: digest.modeName))
            .accessibilityAddTraits(expanded ? .isSelected : [])
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: digest.modeName)
                    .font(.headline)
                    .lineLimit(1)
                times
            }
            Spacer(minLength: 8)
            statusPill
            Menu {
                Button(.badgeMemoryDeleteDigest, systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(.badgeMemoryDeleteDigest))
        }
        .padding(14)
    }

    private var times: some View {
        HStack(spacing: 6) {
            Text(.badgeMemoryStarted)
            Text(digest.started, format: .dateTime.month().day().hour().minute()).monospacedDigit()
            if let ended = digest.ended {
                Text(verbatim: "·")
                Text(.badgeMemoryEnded)
                Text(ended, format: .dateTime.month().day().hour().minute()).monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var statusPill: some View {
        Label {
            Text(collecting ? .badgeMemoryCollecting : .badgeMemoryFinished)
        } icon: {
            Image(systemName: collecting ? "record.circle" : "checkmark.circle")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(collecting ? Color.accentColor : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(collecting ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                               : AnyShapeStyle(.quaternary.opacity(0.7)), in: .capsule)
    }

    /// Coverage gaps are the difference between "nothing happened" and "nothing was seen".
    private var gap: some View {
        Label { Text(.badgeMemoryGap) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: .rect(cornerRadius: 10))
    }
}

/// One app's endpoints inside a session: first observed, last observed, and the net between them.
private struct BadgeDigestRowView: View {
    let path: String
    let row: BadgeDigestRow
    let activate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(nsImage: BadgeAppArtwork.icon(path))
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(verbatim: badgeAppName(path))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(.badgeMemoryChangesCount(row.changes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(action: activate) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help(Text(.badgeMemoryOpenNamedApp(badgeAppName(path))))
                .accessibilityLabel(Text(.badgeMemoryOpenNamedApp(badgeAppName(path))))
            }
            HStack(spacing: 8) {
                BadgeValueChip(value: row.first)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                BadgeValueChip(value: row.last)
                Spacer(minLength: 8)
                BadgeDeltaChip(delta: row.last.delta(from: row.first))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(.badgeMemoryFirst))
            if row.hasGap {
                Label { Text(.badgeMemoryGap) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: 11))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
@MainActor private func badgeDigestPreview(incomplete: Bool) -> BadgeFocusDigest {
    BadgeFocusDigest(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, modeName: "Writing",
                     started: Date(timeIntervalSince1970: 1_700_000_000),
                     ended: incomplete ? nil : Date(timeIntervalSince1970: 1_700_001_500),
                     incomplete: incomplete,
                     rows: ["/Applications/Mail.app": BadgeDigestRow(first: .count(37), last: .cleared,
                                                                     changes: 3, hasGap: true),
                            "/Applications/Messages.app": BadgeDigestRow(first: .count(2), last: .count(9),
                                                                         changes: 5)])
}

#Preview("Net decrease with unavailable coverage") {
    BadgeDigestSection(digest: badgeDigestPreview(incomplete: true), activate: { _ in }, delete: {})
        .padding().frame(width: 620)
}

#Preview("Finished session, German") {
    BadgeDigestSection(digest: badgeDigestPreview(incomplete: false), activate: { _ in }, delete: {})
        .environment(\.locale, Locale(identifier: "de"))
        .padding().frame(width: 620)
}
#endif
