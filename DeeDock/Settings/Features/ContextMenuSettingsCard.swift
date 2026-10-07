import SwiftUI

/// Chooses how a dock tile gets out from under its context menu. App-wide.
struct ContextMenuSettingsCard: View {
    @Binding var selection: DockContextMenuReveal

    var body: some View {
        SettingsCard(title: .contextMenusTitle, footnote: .contextMenusSettingsHelp) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(DockContextMenuReveal.allCases) { reveal in
                    ContextMenuRevealOption(reveal: reveal, isSelected: selection == reveal) {
                        selection = reveal
                    }
                }
            }
            .padding(SettingsMetrics.rowInset)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.contextMenuRevealLabel))
        }
    }
}

/// One style in the gallery: its looping schematic, name, and a line on what it trades.
private struct ContextMenuRevealOption: View {
    let reveal: DockContextMenuReveal
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                ContextMenuRevealThumbnail(reveal: reveal)
                    .frame(height: 70)
                Text(reveal.title).font(.callout.weight(.medium))
                Text(reveal.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(10)
            .settingsSelectionCard(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(reveal.title))
        .accessibilityHint(Text(reveal.subtitle))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A dock strip whose third tile opens a menu, replaying the style on a loop.
///
/// The loop runs on keyframes rather than the dock's own modifier, so the schematic never touches
/// live dock state. Reduce Motion shows the moment the menu is open, without playing.
private struct ContextMenuRevealThumbnail: View {
    let reveal: DockContextMenuReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ContextMenuRevealScene(pose: .open(reveal))
        } else {
            KeyframeAnimator(initialValue: ContextMenuRevealPose.rest, repeating: true) { pose in
                ContextMenuRevealScene(pose: pose)
            } keyframes: { _ in
                ContextMenuRevealPose.keyframes(for: reveal)
            }
        }
    }
}

/// One frame of the schematic. Offsets are fractions of the travel to the tile's spot beside the menu.
private struct ContextMenuRevealPose {
    var travel: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    var menu: Double = 0

    static let rest = Self()

    /// The menu fully open, for Reduce Motion's still frame.
    static func open(_ reveal: DockContextMenuReveal) -> Self {
        Self(travel: reveal == .off ? 0 : 1, scale: reveal == .off ? 1 : DockContextMenuSpotlight.scale, menu: 1)
    }

    /// One 3.4-second cycle: a pause, the menu opening, a hold, the menu closing, and the tile going home.
    @KeyframesBuilder<Self>
    static func keyframes(for reveal: DockContextMenuReveal) -> some Keyframes<Self> {
        let lead = 0.7, hold = 1.5, home = 0.6
        let tail = 3.4 - lead - hold - home
        let pop = Spring(response: 0.42, dampingRatio: 0.58)
        KeyframeTrack(\.travel) {
            LinearKeyframe(0, duration: lead)
            switch reveal {
            case .popOut:
                MoveKeyframe(1)
                LinearKeyframe(1, duration: hold)
            case .slideOut:
                SpringKeyframe(1, duration: hold, spring: Spring(response: 0.24, dampingRatio: 0.86))
            case .off:
                LinearKeyframe(0, duration: hold)
            }
            SpringKeyframe(0, duration: home, spring: Spring(response: 0.3, dampingRatio: 0.82))
            LinearKeyframe(0, duration: tail)
        }
        KeyframeTrack(\.scale) {
            LinearKeyframe(1, duration: lead)
            switch reveal {
            case .popOut:
                MoveKeyframe(0.4)
                SpringKeyframe(DockContextMenuSpotlight.scale, duration: hold, spring: pop)
            case .slideOut:
                SpringKeyframe(DockContextMenuSpotlight.scale, duration: hold, spring: Spring(response: 0.24, dampingRatio: 0.86))
            case .off:
                LinearKeyframe(1, duration: hold)
            }
            SpringKeyframe(1, duration: home, spring: Spring(response: 0.3, dampingRatio: 0.82))
            LinearKeyframe(1, duration: tail)
        }
        KeyframeTrack(\.opacity) {
            LinearKeyframe(1, duration: lead)
            if reveal == .popOut {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.15)
                LinearKeyframe(1, duration: hold - 0.15)
            } else {
                LinearKeyframe(1, duration: hold)
            }
            LinearKeyframe(1, duration: home + tail)
        }
        KeyframeTrack(\.menu) {
            // Slide Out holds the menu back while the tile travels.
            let wait = reveal == .slideOut ? DockContextMenuReveal.slideLead : 0
            LinearKeyframe(0, duration: lead + wait)
            MoveKeyframe(1)
            LinearKeyframe(1, duration: hold - wait)
            LinearKeyframe(0, duration: 0.12)
            LinearKeyframe(0, duration: home + tail - 0.12)
        }
    }
}

/// The drawn schematic: glass strip, four tiles, and a menu hanging up and right from the click.
private struct ContextMenuRevealScene: View {
    let pose: ContextMenuRevealPose

    private let tile: CGFloat = 14
    private let gap: CGFloat = 6
    private let owner = 2

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let count = 4
            let rowWidth = CGFloat(count) * tile + CGFloat(count - 1) * gap
            let originX = (size.width - rowWidth) / 2
            let baseline = size.height - 8
            let ownerX = originX + CGFloat(owner) * (tile + gap) + tile / 2
            // The click lands on the tile's leading quarter, so the menu starts over the tile.
            let pointer = CGPoint(x: ownerX - tile / 4, y: baseline - tile / 2)
            let menu = CGSize(width: 34, height: 40)
            let destination = CGPoint(x: pointer.x - 4 - tile / 2, y: baseline - tile - 10 - tile / 2)
            ZStack(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(width: rowWidth + 12, height: tile + 8)
                    .position(x: size.width / 2, y: baseline - tile / 2)
                ForEach(0..<count, id: \.self) { index in
                    let x = originX + CGFloat(index) * (tile + gap) + tile / 2
                    let isOwner = index == owner
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(isOwner ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: tile, height: tile)
                        .scaleEffect(isOwner ? pose.scale : 1)
                        .opacity(isOwner ? pose.opacity : 1 - 0.55 * pose.menu)
                        .position(x: isOwner ? x + (destination.x - x) * pose.travel : x,
                                  y: (baseline - tile / 2) + (isOwner ? (destination.y - (baseline - tile / 2)) * pose.travel : 0))
                }
                ContextMenuRevealMenu()
                    .frame(width: menu.width, height: menu.height)
                    .position(x: pointer.x + menu.width / 2, y: pointer.y - menu.height / 2)
                    .opacity(pose.menu)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small opaque menu panel with item rows.
private struct ContextMenuRevealMenu: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.background)
            .overlay {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4, id: \.self) { row in
                        Capsule().fill(.tertiary).frame(width: row == 1 ? 14 : 22, height: 3)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

#if DEBUG
    #Preview("Context menus card") {
        @Previewable @State var reveal = DockContextMenuReveal.popOut
        ContextMenuSettingsCard(selection: $reveal)
            .padding(24)
            .frame(width: SettingsMetrics.columnWidth)
            .tint(SettingsPage.contextMenus.tint)
    }

    #Preview("Still frames") {
        HStack(spacing: 12) {
            ForEach(DockContextMenuReveal.allCases) { reveal in
                ContextMenuRevealScene(pose: .open(reveal))
                    .frame(width: 140, height: 70)
            }
        }
        .padding(24)
        .tint(SettingsPage.contextMenus.tint)
    }
#endif
