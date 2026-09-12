import SwiftUI

/// Compost is an archive of references, with its rule and recovery controls kept together.
struct ShelfCompostView: View {
    let state: ShelfPanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    CompostGarden(restoration: state.compostRestoration, reduceMotion: reduceMotion)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(.compostName).font(.title3.bold())
                        Text(.compostTagline).font(.callout).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Picker(selection: Binding(get: { state.compostPolicy }, set: {
                        state.compostPolicyChanged?($0)
                    })) {
                        ForEach(ShelfCompostPolicy.allCases, id: \.self) { rule in
                            Text(rule.title).tag(rule)
                        }
                    } label: {
                        Text(.compostRule)
                    }
                    .disabled(state.compostRequiresReset)
                    Text(.compostRuleHelp)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if state.compostRequiresReset {
                    Label(.compostStorageUnavailable, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                }
                if state.compost.count >= ShelfCompostEntry.capacity {
                    Label(.compostArchiveFull, systemImage: "pause.circle")
                        .font(.callout)
                }
                if let error = state.compostFailure {
                    Label { Text(verbatim: error) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.callout)
                }
                if let notice = state.compostNotice {
                    Label { Text(verbatim: notice) } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.callout)
                }
                Divider()
                if state.compost.isEmpty, !state.compostRequiresReset {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(.compostEmptyTitle).font(.headline)
                        Text(.compostEmptyMessage).font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(state.compost) { entry in
                            ShelfCompostRow(entry: entry,
                                            restore: { state.restoreCompost?(entry.id) },
                                            forget: { state.forgetCompost?(entry.id) })
                                .transition(reduceMotion ? .identity : .asymmetric(
                                    insertion: .opacity,
                                    removal: .offset(y: -12).combined(with: .opacity)))
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state.compost.map(\.id))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.compostName))
    }
}

/// Each row remains restorable even if its file is offline or has moved beyond bookmark recovery.
private struct ShelfCompostRow: View {
    let entry: ShelfCompostEntry
    let restore: () -> Void
    let forget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: entry.item.name).font(.callout.weight(.medium)).lineLimit(2)
                    Text(verbatim: entry.item.url.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(.compostArchived(date: entry.archivedAt.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(action: restore) { Label(.compostRestore, systemImage: "arrow.uturn.backward") }
                    .accessibilityLabel(Text(.compostRestoreNamed(name: entry.item.name)))
                Spacer(minLength: 4)
                Button(.compostForget, role: .destructive, action: forget)
                    .accessibilityLabel(Text(.compostForgetTitle(name: entry.item.name)))
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: entry.item.name))
    }
}

/// A still soil bed with a brief sprout bounce after restoration. No continuous rendering or shaders.
private struct CompostGarden: View {
    let restoration: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
            Ellipse().fill(.brown.opacity(0.22)).frame(width: 70, height: 16).offset(y: -6)
            Ellipse().stroke(.brown.opacity(0.4), lineWidth: 1).frame(width: 58, height: 9).offset(y: -9)
            HStack(spacing: 7) {
                ForEach(0..<5) { index in
                    Circle().fill(.brown.opacity(0.55)).frame(width: 2, height: 2)
                        .offset(y: index.isMultiple(of: 2) ? -10 : -14)
                }
            }
            Group {
                if reduceMotion {
                    Image(systemName: "leaf.fill")
                } else {
                    Image(systemName: "leaf.fill")
                        .symbolEffect(.bounce, options: .nonRepeating, value: restoration)
                }
            }
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.green.gradient)
                .rotationEffect(.degrees(-25))
                .offset(y: -19)
        }
        .frame(width: 84, height: 78)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Compost, German") {
    let state = ShelfPanelState()
    state.compostPolicy = .fortnight
    state.compost = [ShelfCompostEntry(
        item: ShelfItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000055")!,
                        url: URL(fileURLWithPath: "/Preview/Downloads/Quarterly report.pdf"),
                        name: "Quarterly report.pdf", bookmarkData: Data(),
                        addedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        archivedAt: Date(timeIntervalSince1970: 1_702_000_000))]
    return ShelfCompostView(state: state)
        .frame(width: 420, height: 380)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Compost, empty and dark") {
    ShelfCompostView(state: ShelfPanelState())
        .frame(width: 420, height: 380).preferredColorScheme(.dark)
}
#endif
