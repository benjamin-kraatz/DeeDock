import SwiftUI

/// The dock while Harbor is open: only running apps, each with its name and how many windows it
/// has on this display, plus the Harbor tile when the dock shows one.
///
/// When Harbor opens over a visible dock, the strip starts as a copy of that dock
/// (``HarborDockSeed``): the same glass, the same icons at the same, possibly magnified, frames.
/// As `transformed` turns on, pins without windows and other tiles shrink away, the survivors
/// slide together, the glass grows to make room for labels, and window counts pop in. Closing
/// runs it backwards, so the strip lands on the real dock as the backdrop clears. Without a
/// seed, or under Reduce Motion, the strip simply fades in at the display edge.
///
/// Clicking an app with windows here shows only its group; clicking it again shows every group.
/// An app without windows here is brought forward, as the dock would. The Harbor tile closes Harbor.
struct HarborDockStrip: View {
    let apps: [HarborStripApp]
    let counts: [String: Int]
    let icons: [String: NSImage]
    let edge: DockEdge
    let displaySize: CGSize
    let seed: HarborDockSeed?
    let filter: String?
    /// True while Harbor's backdrop is up; the strip then has its own shape rather than the dock's.
    let transformed: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let tap: (String) -> Void
    let closeHarbor: () -> Void

    /// One tile for the current state, whether it survives the transformation or not.
    private struct TileState: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let isHarbor: Bool
        let appID: String?
        let frame: CGRect
        let label: CGRect?
        let count: Int
        let collapsed: Bool
        let selected: Bool
    }

    private var morphs: Bool { seed != nil && !reduceMotion }
    private var showsHarborTile: Bool { seed?.tiles.contains { $0.kind == .harbor } ?? false }

    private var layout: HarborStripLayout {
        var items = apps.map { HarborStripLayout.Item(id: DockEntryID.app($0.id).hitID) }
        if showsHarborTile { items.append(HarborStripLayout.Item(id: DockEntryID.harbor.hitID, gapBefore: true)) }
        return HarborStripLayout.place(items, edge: edge, displaySize: displaySize)
    }

    /// The strip's own shape, or the dock's while not transformed.
    private func glassFrame(_ layout: HarborStripLayout) -> (CGRect, CGFloat) {
        if morphs, !transformed, let seed { return (seed.glass, seed.cornerRadius) }
        return (layout.glass, layout.cornerRadius)
    }

    private func tiles(_ layout: HarborStripLayout) -> [TileState] {
        var result: [TileState] = []
        var placed = Set<String>()
        let seedTiles = morphs ? seed?.tiles ?? [] : []
        // Survivors: running apps and the Harbor tile.
        for app in apps {
            let id = DockEntryID.app(app.id).hitID
            guard let tile = layout.tiles[id] else { continue }
            placed.insert(id)
            let start = seedTiles.first { $0.id == id }?.frame ?? tile.icon
            let home = transformed || !morphs
            result.append(TileState(id: id, name: app.name, icon: icons[app.id], isHarbor: false, appID: app.id,
                                    frame: home ? tile.icon : start, label: tile.label, count: counts[app.id] ?? 0,
                                    // A running app the dock does not show grows in from nothing.
                                    collapsed: !home && seedTiles.first { $0.id == id } == nil,
                                    selected: filter == app.id))
        }
        if showsHarborTile, let tile = layout.tiles[DockEntryID.harbor.hitID] {
            let id = DockEntryID.harbor.hitID
            placed.insert(id)
            let start = seedTiles.first { $0.id == id }?.frame ?? tile.icon
            result.append(TileState(id: id, name: String(localized: .harborName), icon: nil, isHarbor: true, appID: nil,
                                    frame: transformed || !morphs ? tile.icon : start, label: tile.label, count: 0,
                                    collapsed: false, selected: false))
        }
        // Everything else the dock showed shrinks away in place.
        for tile in seedTiles where !placed.contains(tile.id) {
            result.append(TileState(id: tile.id, name: "", icon: tile.icon, isHarbor: tile.kind == .harbor, appID: nil,
                                    frame: tile.frame, label: nil, count: 0, collapsed: transformed, selected: false))
        }
        return result
    }

    var body: some View {
        let layout = layout
        let (glass, radius) = glassFrame(layout)
        let hiddenOffset: CGSize = switch edge {
        case .bottom: CGSize(width: 0, height: 24)
        case .top: CGSize(width: 0, height: -24)
        case .left: CGSize(width: -24, height: 0)
        case .right: CGSize(width: 24, height: 0)
        }
        ZStack(alignment: .topLeading) {
            DockBackgroundView(reduceTransparency: reduceTransparency, cornerRadius: radius)
                .shadow(color: .black.opacity(reduceTransparency ? 0.25 : 0), radius: 15, y: 10)
                .frame(width: glass.width, height: glass.height)
                .position(x: glass.midX, y: glass.midY)
                // The real dock's glass is still visible under a clear backdrop, so the strip's
                // fades in as the backdrop covers it rather than doubling it.
                .opacity(transformed ? 1 : 0)
                .animation(HarborStyle.stripMorph, value: transformed)
            ForEach(tiles(layout)) { tile in
                HarborStripTile(name: tile.name, icon: tile.icon, isHarbor: tile.isHarbor, count: tile.count,
                                selected: tile.selected, collapsed: tile.collapsed, showsDetails: transformed,
                                iconSize: tile.frame.width, labelFrame: tile.label.map { $0.offsetBy(dx: -tile.frame.minX, dy: -tile.frame.minY) },
                                reduceMotion: reduceMotion) {
                    if tile.isHarbor { closeHarbor() } else if let appID = tile.appID { tap(appID) }
                }
                .frame(width: tile.frame.width, height: tile.frame.height)
                .position(x: tile.frame.midX, y: tile.frame.midY)
                .animation(HarborStyle.stripMorph, value: transformed)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .opacity(morphs || transformed ? 1 : 0)
        .offset(morphs || transformed || reduceMotion ? .zero : hiddenOffset)
        .animation(morphs ? nil : transformed ? (reduceMotion ? HarborStyle.fade : HarborStyle.stripMorph) : HarborStyle.chromeOut,
                   value: transformed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.harborRunningApps))
    }
}

/// One tile in the strip: an icon with, once transformed, its name and window count.
struct HarborStripTile: View {
    let name: String
    let icon: NSImage?
    let isHarbor: Bool
    let count: Int
    let selected: Bool
    /// Shrunk and faded: a tile the strip does not keep.
    let collapsed: Bool
    /// Whether labels and counts show; they belong to the transformed strip only.
    let showsDetails: Bool
    let iconSize: CGFloat
    /// The label slot relative to the icon's top-left corner.
    let labelFrame: CGRect?
    let reduceMotion: Bool
    let action: () -> Void
    @State private var hovering = false

    private var interactive: Bool { !collapsed && (isHarbor || !name.isEmpty) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.primary.opacity(0.14))
                        .frame(width: iconSize + 12, height: iconSize + 10)
                        .offset(x: -6, y: -5)
                        .transition(.opacity)
                }
                artwork
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(hovering && interactive && !reduceMotion ? 1.06 : 1)
                    .animation(HarborStyle.hover, value: hovering)
                if count > 0 {
                    HarborCountBadge(count: count)
                        .scaleEffect(showsDetails ? 1 : 0.4)
                        .opacity(showsDetails ? 1 : 0)
                        .animation(showsDetails ? HarborStyle.badgeIn : HarborStyle.chromeOut, value: showsDetails)
                        .frame(width: iconSize, height: iconSize, alignment: .topTrailing)
                        .offset(x: 6, y: -5)
                }
                if let labelFrame, !name.isEmpty {
                    Text(verbatim: name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .frame(width: labelFrame.width, height: labelFrame.height)
                        .offset(x: labelFrame.minX, y: labelFrame.minY)
                        .opacity(showsDetails ? 1 : 0)
                        .animation(showsDetails ? .easeOut(duration: 0.25).delay(0.15) : HarborStyle.chromeOut, value: showsDetails)
                }
            }
            .frame(width: iconSize, height: iconSize, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(collapsed ? 0.35 : 1)
        .opacity(collapsed ? 0 : 1)
        .onHover { hovering = $0 }
        .allowsHitTesting(interactive)
        .accessibilityHidden(!interactive)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(isHarbor ? Text(verbatim: "") : Text(.harborWindowCount(count)))
        .accessibilityHint(isHarbor ? Text(.harborStripCloseHint) : Text(verbatim: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var artwork: some View {
        if isHarbor {
            HarborGlyph(size: iconSize)
                .shadow(color: Color(red: 0.55, green: 0.67, blue: 1).opacity(showsDetails ? 0.85 : 0), radius: 9)
                .animation(.easeOut(duration: 0.3), value: showsDetails)
        } else if let icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Color.clear
        }
    }
}

/// The window count on a strip tile: a grey capsule, as the dock's own badges.
struct HarborCountBadge: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 19, minHeight: 19)
            .background(Capsule().fill(Color(red: 0.56, green: 0.56, blue: 0.58)))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Strip, transformed") {
    HarborDockStrip(apps: [HarborStripApp(id: "safari", name: "Safari", processIdentifier: 1),
                           HarborStripApp(id: "preview", name: "Vorschau", processIdentifier: 2),
                           HarborStripApp(id: "mail", name: "Mail", processIdentifier: 3)],
                    counts: ["safari": 5, "preview": 2], icons: [:], edge: .bottom,
                    displaySize: CGSize(width: 640, height: 220), seed: HarborPreviewData.dockSeed, filter: "safari",
                    transformed: true, reduceMotion: false, reduceTransparency: false, tap: { _ in }, closeHarbor: {})
        .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}

#Preview("Strip, as the dock") {
    HarborDockStrip(apps: [HarborStripApp(id: "safari", name: "Safari", processIdentifier: 1),
                           HarborStripApp(id: "preview", name: "Vorschau", processIdentifier: 2),
                           HarborStripApp(id: "mail", name: "Mail", processIdentifier: 3)],
                    counts: ["safari": 5, "preview": 2], icons: [:], edge: .bottom,
                    displaySize: CGSize(width: 640, height: 220), seed: HarborPreviewData.dockSeed, filter: nil,
                    transformed: false, reduceMotion: false, reduceTransparency: false, tap: { _ in }, closeHarbor: {})
        .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}
#endif
