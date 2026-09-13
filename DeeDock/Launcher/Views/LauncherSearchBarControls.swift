import SwiftUI

/// One search-field overflow for type, filters, layout, and file actions.
///
/// File-action mode keeps Choose Files and hides browse-only items. A discrete result type
/// replaces the app filter and location, sort, group, and layout pickers with result actions.
struct LauncherSearchBarOverflowMenu: View {
    @Bindable var state: LauncherState

    var body: some View {
        @Bindable var search = state.search
        Menu {
            if !state.usesFileActions {
                Picker(selection: $search.kind) {
                    ForEach(LauncherSearchKind.allCases) { kind in
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                        .tag(kind)
                    }
                } label: {
                    Text(.unifiedTypeFilter)
                }
                if hasDiscreteKindSelected {
                    mixedResultActions
                } else {
                    appsFilter
                    locationSortGroup
                    layout
                }
                Divider()
            }
            chooseFiles
            if !state.usesFileActions {
                capture
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(LauncherSearchAccessoryButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(.launcherSearchOverflow))
        .help(Text(.launcherSearchOverflowHelp))
        .onChange(of: search.kind) {
            state.cancelRobi()
            state.keyboardNavigationActive = false
        }
    }

    private var hasDiscreteKindSelected: Bool {
        state.search.kind != .all && state.search.kind != .application
    }

    private var appsFilter: some View {
        Picker(selection: $state.filter) {
            ForEach(LauncherFilter.allCases) { filter in
                Label {
                    Text(filter.title)
                } icon: {
                    Image(systemName: filter.symbol)
                }
                .tag(filter)
            }
        } label: {
            Text(.launcherFilter)
        }
    }

    @ViewBuilder private var locationSortGroup: some View {
        Picker(selection: $state.locationFilter) {
            ForEach(LauncherLocationFilter.allCases) { location in
                Text(location.title).tag(location)
            }
        } label: {
            Text(.launcherLocation)
        }
        Picker(selection: $state.sort) {
            ForEach(LauncherSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        } label: {
            Text(.launcherSort)
        }
        Picker(selection: $state.grouping) {
            ForEach(LauncherGrouping.allCases) { group in
                Text(group.title).tag(group)
            }
        } label: {
            Text(.launcherGroup)
        }
    }

    private var layout: some View {
        Picker(selection: $state.layout) {
            ForEach(LauncherLayout.allCases) { layout in
                Label {
                    Text(layout.title)
                } icon: {
                    Image(systemName: layout.symbol)
                }
                .tag(layout)
            }
        } label: {
            Text(.launcherView)
        }
    }

    @ViewBuilder private var mixedResultActions: some View {
        if let result = mixedResultActionTarget {
            Divider()
            LauncherMixedResultMenu(result: result, launcher: state)
        }
    }

    private var chooseFiles: some View {
        Button {
            state.fileActions.chooseFiles()
        } label: {
            Label {
                Text(.launcherFileChooseFiles)
            } icon: {
                Image(systemName: "doc.badge.plus")
            }
        }
    }

    private var capture: some View {
        Button {
            state.search.explicitSearch?()
        } label: {
            Label {
                Text(.unifiedCaptureRoute)
            } icon: {
                Image(systemName: "camera.viewfinder")
            }
        }
    }

    private var mixedResultActionTarget: LauncherSearchResult? {
        guard let selectedID = state.search.selectedID else {
            return state.search.visible.first
        }

        return state.search.visible.first { $0.id == selectedID }
    }
}

/// Ask Robi, visible only for a trimmed nonempty query. Cancel stays available while a request runs.
struct LauncherRobiButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState

    var body: some View {
        Group {
            if hasQuery {
                button
                    .transition(.blurReplace)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: hasQuery)
    }

    private var hasQuery: Bool {
        !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var button: some View {
        Button {
            if state.robiBusy { state.cancelRobi() } else { state.askRobi() }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if state.robiBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .frame(width: 14)
                .accessibilityHidden(true)
                Text(state.robiBusy ? .launcherRobiCancel : .launcherAskRobi)
                    .lineLimit(1)
                    .fixedSize()
                if !state.robiBusy {
                    Text(verbatim: "⌘↩")
                        .font(.caption.weight(.medium))
                        .opacity(0.55)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(LauncherRobiButtonStyle())
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(
            Text(state.robiBusy ? .launcherRobiCancel : .launcherAskRobi)
        )
        .disabled(!state.hasLocationMatchingApplications)
        .help(Text(.launcherRobiHelp))
    }
}

/// A tinted text capsule the same height as the field's icon buttons, so Robi sits in line with them.
private struct LauncherRobiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RobiLabel(configuration: configuration)
    }

    private struct RobiLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.body.weight(.medium))
                .foregroundStyle(LauncherRobiTint.label(colorScheme))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    LauncherRobiTint.fill(pressed: configuration.isPressed, hovering: hovering),
                    in: .capsule
                )
                .contentShape(.capsule)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.snappy(duration: 0.15), value: hovering)
        }
    }
}

/// Robi's tint: a solid accent wash, with the label lifted toward white on dark glass for contrast.
enum LauncherRobiTint {
    static func label(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.accentColor.mix(with: .white, by: 0.35) : .accentColor
    }

    static func fill(pressed: Bool = false, hovering: Bool) -> Color {
        Color.accentColor.opacity(pressed ? 0.45 : hovering ? 0.36 : 0.28)
    }
}
