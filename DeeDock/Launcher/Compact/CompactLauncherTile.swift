import SwiftUI

/// One app in the compact grid: artwork, name, and the same context menu as the full Launcher.
///
/// A suggested tile opens through ``LauncherState/openSuggested(_:)``, which rechecks that the app
/// still exists and records the acceptance, and adds the suggestion feedback actions.
///
/// Draws the app's line glyph when the dock uses Line icons in the Launcher, and its native icon
/// otherwise. Icons load per tile, so a long library only decodes what the grid shows.
struct CompactLauncherTile: View {
    let application: LauncherApplication
    let launcher: LauncherState
    let selected: Bool
    var isSuggestion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var icon: NSImage?
    @State private var hovered = false

    private var running: Bool { launcher.catalog.runningIDs.contains(application.id) }
    private var busy: Bool { launcher.catalog.launching.contains(application.id) }

    var body: some View {
        Button {
            if isSuggestion { launcher.openSuggested(application) }
            else { launcher.open(application) }
        } label: {
            VStack(spacing: 6) {
                artwork
                Text(application.reference.name.replacingOccurrences(of: "\u{00ad}", with: ""))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .frame(width: CompactLauncherLayout.tileWidth, height: CompactLauncherLayout.tileHeight)
            .background(background, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovered = $0 }
        .contextMenu {
            LauncherApplicationMenu(application: application, state: launcher, isSuggestion: isSuggestion)
            if isSuggestion {
                Divider()
                LauncherSuggestionActions(application: application, state: launcher)
            }
        }
        .task(id: application.reference.url) { icon = launcher.icon(for: application) }
        .help(Text(verbatim: application.reference.url.path))
        .accessibilityLabel(Text(application.reference.name))
        .accessibilityValue(Text(running ? .launcherRunning : .launcherNotRunning))
        .accessibilityHint(Text(.launcherOpenHint))
        .accessibilityActions {
            if isSuggestion { LauncherSuggestionActions(application: application, state: launcher) }
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var background: Color {
        selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(hovered ? 0.08 : 0)
    }

    private var artwork: some View {
        let size = CompactLauncherLayout.iconSize
        return ZStack(alignment: .bottom) {
            Group {
                if let lineIcon = launcher.lineIcon(for: application, artwork: icon) {
                    DockLineIconArtwork(icon: lineIcon, size: size, hovered: hovered || selected,
                                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                        color: .primary)
                } else if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            if running {
                Circle().fill(.primary.opacity(0.65)).frame(width: 4, height: 4).offset(y: 5)
            }
            if busy {
                ProgressView().controlSize(.small).frame(width: size, height: size)
                    .background(.regularMaterial, in: .circle)
            }
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }
}
