import SwiftUI

/// Lazy results keep native icon loading proportional to visible content; stable IDs survive sorting and filtering.
struct LauncherResultsView: View {
    let state: LauncherState
    let columns: Int
    let groups: [LauncherState.Group]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if groups.allSatisfy({ $0.applications.isEmpty }) {
                    ContentUnavailableView {
                        Label {
                            Text(
                                state.library.isLoading
                                    ? .launcherDiscovering : .launcherNoResults
                            )
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    } description: {
                        Text(.launcherNoResultsDetail)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading) {
                                if !group.id.isEmpty {
                                    Text(group.id).font(.headline).foregroundStyle(
                                        .secondary
                                    )
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.leading, 12)
                                }
                                if state.layout == .grid {
                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(
                                                .flexible(),
                                                spacing: 0
                                            ),
                                            count: columns
                                        ),
                                        spacing: 0
                                    ) {
                                        ForEach(group.applications) { app in
                                            result(app)
                                        }
                                    }
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(group.applications) { app in
                                            result(app)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
            .onChange(of: state.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: groups.flatMap(\.applications).map(\.id)) { _, ids in
                if let selected = state.selectedID, !ids.contains(selected) {
                    state.selectedID = nil
                }
            }
        }
    }

    private func result(_ application: LauncherApplication) -> some View {
        LauncherResultButton(application: application, state: state).id(
            application.id
        )
    }
}

private struct LauncherResultButton: View {
    let application: LauncherApplication
    let state: LauncherState
    @State private var icon: NSImage?
    @State private var hovered = false

    private var selected: Bool { state.selectedID == application.id }
    private var pinned: Bool { state.pinnedIDs.contains(application.id) }
    private var running: Bool {
        state.catalog.runningIDs.contains(application.id)
    }
    private var busy: Bool { state.catalog.launching.contains(application.id) }

    var body: some View {
        Button {
            state.open(application)
        } label: {
            Group {
                if state.layout == .grid {
                    VStack(spacing: 8) {
                        artwork(size: 60)
                        Text(
                            application.reference.name.replacingOccurrences(
                                of: "\u{00ad}",
                                with: ""
                            )
                        ).font(.callout).lineLimit(2)
                            .allowsTightening(true).minimumScaleFactor(0.9)
                            .multilineTextAlignment(.center).frame(
                                height: 34,
                                alignment: .top
                            )
                    }
                    .padding(10).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 12) {
                        artwork(size: 34)
                        Text(application.reference.name).font(.body.bold()).lineLimit(
                            1
                        )
                        Spacer()
                        Text(LauncherCategory.title(application.category)).font(
                            .caption
                        ).foregroundStyle(.secondary)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                selected
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(hovered ? 0.06 : 0),
                in: .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(
                    selected ? Color.accentColor : .clear,
                    lineWidth: 2
                )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(busy)
        .contextMenu {
            LauncherApplicationMenu(application: application, state: state)
        }
        .onHover { hovered = $0 }
        .task(id: application.reference.url) {
            icon = state.icon(for: application)
        }
        .accessibilityLabel(Text(application.reference.name))
        .accessibilityValue(
            pinned
                ? Text(
                    running ? .launcherPinnedRunning : .launcherPinnedNotRunning
                )
                : Text(running ? .launcherRunning : .launcherNotRunning)
        )
        .accessibilityHint(Text(.launcherOpenHint))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(application.reference.url.path)
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            if running {
                Circle().fill(.primary.opacity(0.65)).frame(width: 4, height: 4)
                    .offset(y: 5)
            }
            if busy {
                ProgressView().controlSize(.small).frame(
                    width: size,
                    height: size
                ).background(.regularMaterial, in: .circle)
            }
        }
        .overlay(alignment: .topTrailing) {
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: size * 0.19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Color.accentColor, in: .circle)
                    .overlay {
                        Circle().strokeBorder(.background, lineWidth: 1.5)
                    }
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .accessibilityHidden(true)
    }
}
