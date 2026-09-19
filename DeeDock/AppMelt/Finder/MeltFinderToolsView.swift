import SwiftUI

/// Finder-only header affordance; its popover owns no file work or window polling.
struct MeltFinderToolsButton: View {
    @Bindable var state: MeltFinderState
    var body: some View {
        Button { state.isPresented.toggle() } label: {
            ZStack {
                Image(systemName: "folder.badge.gearshape").opacity(state.busy ? 0 : 1)
                if state.busy { ProgressView().controlSize(.small) }
            }.frame(width: 38, height: 32)
        }
        .buttonStyle(AppMeltToolbarButtonStyle(selected: state.isPresented))
        .help(Text(.meltFinderTools))
        .accessibilityLabel(Text(.meltFinderTools))
        .popover(isPresented: $state.isPresented, arrowEdge: .bottom) {
            MeltFinderToolsView(state: state)
                .onAppear { if !state.isChoosingFolder { state.refresh() } }
                .onDisappear { state.isPresented = false; state.cancel() }
        }
    }
}

private struct MeltFinderToolsView: View {
    @Bindable var state: MeltFinderState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(.meltFinderTools, systemImage: "folder.badge.gearshape").font(.title2.bold())
                Spacer()
                Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help(Text(.meltFinderRefresh)).disabled(state.busy)
            }
            HStack(spacing: 12) {
                folder(0)
                MeltFinderFlow(leftward: state.direction == .left, busy: state.busy,
                    success: state.success, reduceMotion: reduceMotion)
                    .frame(width: 76, height: 56)
                folder(1)
            }
            Picker(.meltFinderDirection, selection: $state.direction) {
                Text(.meltFinderRight).tag(MeltFinderState.Direction.right)
                Text(.meltFinderLeft).tag(MeltFinderState.Direction.left)
            }
            .pickerStyle(.segmented).disabled(state.busy)
            HStack {
                Button(.meltFinderNavigate) { state.navigate() }
                    .buttonStyle(.bordered)
                Button(.meltFinderPreview) { state.preview() }
                    .buttonStyle(.glassProminent)
            }.disabled(state.busy || state.locations.count != 2)
            Text(.meltFinderMergeNote).font(.caption).foregroundStyle(.secondary)
            if let plan = state.plan {
                Divider()
                Toggle(.meltFinderReplace, isOn: $state.replacing).disabled(state.busy)
                if plan.entries.isEmpty {
                    Label(.meltFinderIdentical, systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(plan.entries) { entry in
                                HStack(spacing: 10) {
                                    Image(systemName: symbol(entry.kind)).foregroundStyle(color(entry.kind))
                                    Text(verbatim: entry.path).lineLimit(1).truncationMode(.middle)
                                        .help(entry.path)
                                    Spacer()
                                    Text(label(entry.kind)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(10)
                    }
                    .frame(maxHeight: 200)
                    .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
                    Button(.meltFinderApply) { state.apply() }
                        .buttonStyle(.glassProminent).disabled(state.busy || state.actionableCount == 0)
                }
            }
            if state.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    if state.applying {
                        Text(verbatim: state.completed.formatted()).monospacedDigit()
                        Text(.meltFinderProcessed)
                    } else { Text(.meltFinderWorking) }
                    Spacer()
                    Button(.meltFinderCancel) { state.cancel() }
                }.font(.callout)
            }
            if let message = state.message {
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let detail = state.detail, !detail.isEmpty {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(4).textSelection(.enabled)
                }
            }
        }
        .padding(20).frame(width: 520)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.plan != nil)
    }

    private func folder(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(index == 0 ? .meltFinderLeftFolder : .meltFinderRightFolder, systemImage: "folder.fill")
                .font(.caption).foregroundStyle(.secondary)
            if state.locations.indices.contains(index) {
                let url = state.locations[index].url
                Text(verbatim: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
                    .font(.headline).lineLimit(1)
                Text(verbatim: url.path).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).help(url.path)
                if state.hasGrant(index) {
                    Label(.meltFinderAccessGranted, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Button(.meltFinderGrant) { state.grant(index) }
                        .font(.caption).disabled(state.busy || state.isChoosingFolder)
                }
            } else { Text(.meltFinderUnavailable).font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func symbol(_ kind: MeltSyncEntry.Kind) -> String {
        switch kind { case .add: "plus.circle"; case .directory: "folder.badge.plus"; case .replace: "arrow.triangle.2.circlepath"; case .blocked: "exclamationmark.triangle" }
    }
    private func color(_ kind: MeltSyncEntry.Kind) -> Color {
        kind == .blocked || kind == .replace ? .orange : .accentColor
    }
    private func label(_ kind: MeltSyncEntry.Kind) -> LocalizedStringResource {
        switch kind { case .add: .meltFinderAdd; case .directory: .meltFinderFolder; case .replace: .meltFinderConflict; case .blocked: .meltFinderSkipped }
    }
}

/// Only the small direction indicator animates. No full-window overlay obscures file previews.
private struct MeltFinderFlow: View {
    let leftward: Bool
    let busy: Bool
    let success: Int
    let reduceMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !busy || reduceMotion)) { context in
            ZStack {
                Image(systemName: leftward ? "arrow.left" : "arrow.right")
                    .font(.title2.weight(.semibold)).foregroundStyle(.cyan)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: leftward)
                if busy, !reduceMotion {
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    Circle().fill(.cyan).frame(width: 5, height: 5)
                        .shadow(color: .cyan.opacity(reduceTransparency ? 0 : 0.8), radius: 5)
                        .offset(x: (phase * 56 - 28) * (leftward ? -1 : 1), y: 17)
                }
            }
            .frame(width: 70, height: 52)
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear)
            .glassEffect(.regular.tint(.cyan.opacity(0.12)), in: .capsule)
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : success)
        }.accessibilityHidden(true)
    }
}
