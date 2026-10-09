import SwiftUI

/// One app in the Apps tab's grid or list, in browsing and in mixed search.
///
/// The grid tile follows the mockup (`.ag`): a 56 pt real icon (or its line glyph), a running dot,
/// a hover wash with a 1.06 icon lift, press feedback, and an accent selection ring. Favorite and pin badges,
/// the launch spinner, and the full app context menu are kept from the launcher.
struct LauncherResultButton: View {
    let application: LauncherApplication
    let state: LauncherState
    /// Mixed search retains typed membership and action guards; ordinary browsing uses its existing owner directly.
    var searchResult: LauncherSearchResult? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var icon: NSImage?
    @State private var hovered = false
    @State private var hoveredBadge: Badge?

    private enum Badge { case favorite, pinned }

    private var selected: Bool {
        state.usesMixedResults ? state.search.selectedID == .application(application.id)
            : state.selectedID == .application(application.id)
    }
    private var favorite: Bool { state.favorites.ids.contains(application.id) }
    private var pinned: Bool { state.pinnedIDs.contains(application.id) }
    private var running: Bool { state.catalog.runningIDs.contains(application.id) }
    private var busy: Bool { state.catalog.launching.contains(application.id) }
    private var interactionBlocked: Bool {
        busy || (searchResult != nil && (state.search.actionBusy || state.search.ranking || !state.search.active))
    }
    private var displayName: String { application.reference.name.replacingOccurrences(of: "\u{00ad}", with: "") }

    var body: some View {
        Button {
            if let searchResult { state.search.activate(searchResult) } else { state.open(application) }
        } label: {
            Group {
                if state.layout == .grid { gridLabel } else { listLabel }
            }
            .background(hovered ? HubAppsStyle.chip(colorScheme) : .clear,
                        in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.hubPress(scale: state.layout == .grid ? 0.95 : 0.985))
        .disabled(interactionBlocked)
        .contextMenu {
            LauncherApplicationMenu(application: application, state: state, searchResult: searchResult)
        }
        .onHover { inside in
            hovered = inside
            if !inside { hoveredBadge = nil }
        }
        .animation(reduceMotion ? nil : HubStyle.hover, value: hovered)
        .task(id: application.reference.url) {
            icon = state.icon(for: application)
        }
        .accessibilityLabel(Text(application.reference.name))
        .accessibilityValue(LauncherApplicationStatus.text(favorite: favorite, pinned: pinned, running: running))
        .accessibilityHint(Text(.launcherOpenHint))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        // The outer Button owns the native tooltip, so nested badge help cannot override it.
        .help(hoverHelp)
    }

    private var cornerRadius: CGFloat { state.layout == .grid ? HubAppsStyle.tileCornerRadius : HubStyle.rowRadius }

    private var gridLabel: some View {
        VStack(spacing: 8) {
            artwork(size: HubAppsStyle.tileIconSize)
                .scaleEffect(hovered && !reduceMotion ? HubAppsStyle.tileHoverScale : 1)
            Text(displayName)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 12, leading: 4, bottom: 10, trailing: 4))
        .frame(maxWidth: .infinity)
    }

    private var listLabel: some View {
        HStack(spacing: 12) {
            artwork(size: HubAppsStyle.listIconSize)
            Text(displayName).font(.body.weight(.medium)).lineLimit(1)
            Spacer()
            Text(LauncherCategory.title(application.category)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hoverHelp: Text {
        switch hoveredBadge {
        case .favorite where favorite: Text(.launcherFavoriteBadgeHelp)
        case .pinned where pinned: Text(.launcherPinnedBadgeHelp)
        default: Text(verbatim: application.reference.url.path)
        }
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack {
            Group {
                if let lineIcon = state.lineIcon(for: application, artwork: icon) {
                    DockLineIconArtwork(icon: lineIcon, size: size, hovered: hovered || selected,
                                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                        color: .primary)
                } else if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            if busy {
                ProgressView().controlSize(.small)
                    .frame(width: size, height: size)
                    .background(.regularMaterial, in: .circle)
            }
        }
        .overlay(alignment: .bottom) {
            if running {
                Circle().fill(.secondary).frame(width: 4, height: 4).offset(y: 5)
            }
        }
        .overlay(alignment: .topLeading) {
            if favorite {
                LauncherBadge(symbol: "star.fill", size: size, fill: AnyShapeStyle(Color.orange.gradient),
                              stroke: AnyShapeStyle(Color.white.opacity(0.45)), strokeWidth: 0.75)
                    .onHover { inside in
                        if inside { hoveredBadge = .favorite } else if hoveredBadge == .favorite { hoveredBadge = nil }
                    }
                    .offset(x: -size * 0.02, y: -size * 0.01)
            }
        }
        .overlay(alignment: .topTrailing) {
            if pinned {
                LauncherBadge(symbol: "pin.fill", size: size, fill: AnyShapeStyle(Color.accentColor),
                              stroke: AnyShapeStyle(BackgroundStyle()), strokeWidth: 1.5)
                    .onHover { inside in
                        if inside { hoveredBadge = .pinned } else if hoveredBadge == .pinned { hoveredBadge = nil }
                    }
                    .offset(x: size * 0.04, y: -size * 0.02)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The favorite star or pin badge on an app icon's top corner, scaled to the icon.
private struct LauncherBadge: View {
    let symbol: String
    let size: CGFloat
    let fill: AnyShapeStyle
    let stroke: AnyShapeStyle
    let strokeWidth: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 0.32, height: size * 0.32)
            .background(fill, in: .circle)
            .overlay { Circle().strokeBorder(stroke, lineWidth: strokeWidth) }
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            .contentShape(.circle)
    }
}

/// VoiceOver status for an app: pinned and running state, prefixed by Favorite when it is one.
enum LauncherApplicationStatus {
    static func text(favorite: Bool, pinned: Bool, running: Bool) -> Text {
        let status = pinned
            ? String(localized: running ? .launcherPinnedRunning : .launcherPinnedNotRunning)
            : String(localized: running ? .launcherRunning : .launcherNotRunning)
        return favorite ? Text(.launcherFavoriteStatus(status: status)) : Text(verbatim: status)
    }
}
