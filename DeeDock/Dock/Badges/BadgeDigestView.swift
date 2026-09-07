import SwiftUI

struct BadgeDigestView: View {
    let memory: BadgeMemoryStore
    let activate: (String) -> Void
    private var digests: [BadgeFocusDigest] {
        (memory.document.active.map { [$0] } ?? []) + memory.document.digests
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(.badgeMemoryDigestHelp).foregroundStyle(.secondary)
                if digests.isEmpty { Text(.badgeMemoryDigestEmpty) }
                ForEach(digests) { digest in
                    BadgeDigestSection(digest: digest, activate: activate, delete: { memory.deleteDigest(digest.id) })
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BadgeDigestSection: View {
    let digest: BadgeFocusDigest
    let activate: (String) -> Void
    let delete: () -> Void
    @State private var expanded = true
    @State private var confirmsDelete = false
    private var paths: [String] { digest.rows.keys.filter { digest.rows[$0]!.changes > 0 }.sorted() }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(digest.started, format: .dateTime.year().month().day().hour().minute())
                if let ended = digest.ended { Text(ended, format: .dateTime.year().month().day().hour().minute()) }
                if digest.incomplete { Text(.badgeMemoryGap).foregroundStyle(.secondary) }
                if paths.isEmpty { Text(.badgeMemoryNoChanges) }
                ForEach(paths, id: \.self) { path in
                    if let row = digest.rows[path] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: badgeAppName(path)).font(.headline)
                            LabeledContent { BadgeValueText(value: row.first) } label: { Text(.badgeMemoryFirst) }
                            LabeledContent { BadgeValueText(value: row.last) } label: { Text(.badgeMemoryLast) }
                            if let delta = row.last.delta(from: row.first) {
                                Text(.badgeMemoryNet(delta.formatted(.number.sign(strategy: .always()))))
                            } else { Text(.badgeMemoryNoDelta) }
                            if row.hasGap { Text(.badgeMemoryGap).font(.caption) }
                            Button(.badgeMemoryOpenNamedApp(badgeAppName(path))) { activate(path) }
                        }
                        .accessibilityElement(children: .contain)
                        Divider()
                    }
                }
                Button(.badgeMemoryDeleteDigest, role: .destructive) { confirmsDelete = true }
            }.padding(.top, 8)
        } label: {
            HStack {
                Text(verbatim: digest.modeName).font(.headline)
                Text(digest.ended == nil ? .badgeMemoryCollecting : .badgeMemoryFinished).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(.badgeMemoryDeleteDigest, isPresented: $confirmsDelete) {
            Button(.badgeMemoryDeleteDigest, role: .destructive, action: delete)
        } message: { Text(.badgeMemoryDeleteDigestHelp) }
    }
}

#if DEBUG
#Preview("Net decrease with unavailable coverage") {
    BadgeDigestSection(digest: BadgeFocusDigest(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, modeName: "Writing",
        started: Date(timeIntervalSince1970: 1_700_000_000), ended: Date(timeIntervalSince1970: 1_700_001_500),
        incomplete: true, rows: ["/Applications/Mail.app": BadgeDigestRow(first: .count(37), last: .cleared, changes: 3, hasGap: true)]),
        activate: { _ in }, delete: {})
        .padding().frame(width: 600)
}
#endif
