import SwiftUI

/// One display's Harbor: backdrop, app groups, windows, search, and the running-apps strip.
///
/// Geometry comes from the session's layout for this display, in the panel's top-left, y-down
/// space, which matches the display's Quartz bounds. Each window's position depends on the phase:
///
/// - `entering` and `leaving`: windows with a thumbnail sit exactly over their real window, so the
///   switch to and from the desktop is seamless. Windows without one wait, invisible, in the grid.
/// - `open`: every window sits in its grid slot.
///
/// The coordinator changes the phase inside `withAnimation`, so the same views fly both ways. The
/// chrome around the windows keeps its own timing (see ``HarborStyle``): the backdrop, header, and
/// strip move with `showsBackdrop`, ahead of the flight; cards, captions, and chips follow the
/// flight with short delays and leave quickly.
struct HarborView: View {
    let session: HarborSession
    let displayID: String
    let intents: any HarborIntents
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let content = session.displays[displayID] {
            ZStack(alignment: .topLeading) {
                backdrop(content)
                stage(content)
                if displayID == session.keyDisplayID { header(content) }
                emptyState(content)
                strip(content)
            }
            .frame(width: content.size.width, height: content.size.height, alignment: .topLeading)
        }
    }

    // MARK: Layers

    private func backdrop(_ content: HarborDisplayContent) -> some View {
        HarborBackdrop(wallpaper: content.wallpaper, reduceTransparency: session.reduceTransparency)
            .frame(width: content.size.width, height: content.size.height)
            .opacity(session.showsBackdrop ? 1 : 0)
            .animation(session.reduceMotion ? HarborStyle.fade
                       : session.showsBackdrop ? HarborStyle.backdropIn : HarborStyle.backdropOut,
                       value: session.showsBackdrop)
            .contentShape(.rect)
            .onTapGesture { intents.dismiss() }
    }

    /// Groups, windows, captions, and chips. When the layout does not fit even at the smallest
    /// thumbnail size, the stage scrolls; the keyboard selection scrolls into view.
    @ViewBuilder
    private func stage(_ content: HarborDisplayContent) -> some View {
        if content.layout.overflows {
            let bounds = content.layoutBounds(showsSearch: displayID == session.keyDisplayID,
                                              showsNotice: displayID == session.keyDisplayID && !session.access.windows)
            let height = bounds.minY + content.layout.contentHeight + (content.size.height - bounds.maxY)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        // The wallpaper's own tap target is below the scroll view; keep a click on
                        // empty stage space closing Harbor here too.
                        Color.clear.contentShape(.rect).onTapGesture { intents.dismiss() }
                        layers(content)
                    }
                    .frame(width: content.size.width, height: height, alignment: .topLeading)
                }
                .frame(width: content.size.width, height: content.size.height)
                .onChange(of: session.selected) { _, selected in
                    guard let selected else { return }
                    withAnimation(session.reduceMotion ? nil : HarborStyle.motion) { proxy.scrollTo(selected) }
                }
            }
        } else {
            layers(content)
        }
    }

    private func layers(_ content: HarborDisplayContent) -> some View {
        ZStack(alignment: .topLeading) {
            groups(content)
            windows(content)
            captions(content)
            chips(content)
        }
        .frame(width: content.size.width, height: content.size.height, alignment: .topLeading)
    }

    private func groups(_ content: HarborDisplayContent) -> some View {
        ForEach(content.shownGroups) { group in
            if let rect = content.layout.groups[group.id] {
                HarborGroupCard(name: group.name, count: group.count, icon: session.icons[group.id],
                                highlighted: session.highlightedAppID == group.id,
                                reduceMotion: session.reduceMotion, reduceTransparency: session.reduceTransparency)
                    .frame(width: rect.width, height: rect.height)
                    .scaleEffect(session.showsGrid || session.reduceMotion ? 1 : 0.965)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(session.showsGrid ? 1 : 0)
                    .animation(session.showsGrid ? HarborStyle.cardIn : HarborStyle.chromeOut, value: session.showsGrid)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
            }
        }
    }

    private func windows(_ content: HarborDisplayContent) -> some View {
        ForEach(tiles(content), id: \.window.id) { tile in
            let window = tile.window
            let name = content.groups.first { $0.id == window.appID }?.name ?? ""
            let scale = tile.rect.width / max(window.frame.width, 1)
            HarborWindowTile(
                title: window.title ?? name, appName: name, icon: session.icons[window.appID],
                thumbnail: session.thumbnails[window.id], size: tile.rect.size,
                cornerRadius: max(HarborStyle.minimumThumbnailCornerRadius * min(1, scale * 4),
                                  HarborStyle.windowCornerRadius * scale),
                highlighted: session.showsGrid && (session.hovered == window.id || session.selected == window.id),
                lifted: session.showsGrid && (session.hovered == window.id || session.selected == window.id),
                canClose: session.showsGrid && window.token != nil && session.access.windows,
                reduceMotion: session.reduceMotion,
                hover: { inside in
                    if inside { session.hovered = window.id } else if session.hovered == window.id { session.hovered = nil }
                },
                activate: { intents.activate(window.id) },
                close: { intents.closeWindow(window.id) })
            .frame(width: tile.rect.width + 2 * HarborWindowTile.hoverMargin,
                   height: tile.rect.height + 2 * HarborWindowTile.hoverMargin)
            // A window with nothing to fly from grows into its slot instead of just appearing.
            .scaleEffect(tile.visible || session.reduceMotion ? 1 : 0.92)
            .position(x: tile.rect.midX, y: tile.rect.midY)
            .opacity(tile.visible ? 1 : 0)
            .zIndex(tile.zIndex)
            .allowsHitTesting(session.showsGrid)
            .transition(.opacity)
            .id(window.id)
        }
    }

    private func captions(_ content: HarborDisplayContent) -> some View {
        ForEach(content.shownGroups.flatMap(\.windows)) { window in
            if let rect = content.layout.captions[window.id] {
                HarborCaption(title: window.title ?? content.groups.first { $0.id == window.appID }?.name ?? "",
                              subtitle: content.layout.tallCaptions
                                ? HarborCaptionText.subtitle(document: window.document, title: window.title) : nil)
                    .frame(width: rect.width, height: rect.height, alignment: .top)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(session.showsGrid ? 1 : 0)
                    .animation(session.showsGrid ? HarborStyle.captionIn : HarborStyle.chromeOut, value: session.showsGrid)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    private func chips(_ content: HarborDisplayContent) -> some View {
        ForEach(content.shownGroups) { group in
            ForEach(group.tucked) { window in
                if let rect = content.layout.chips[window.id] {
                    HarborWindowChip(title: window.title ?? group.name, state: window.state,
                                     icon: session.icons[group.id]) { intents.activate(window.id) }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(session.showsGrid ? 1 : 0)
                        .animation(session.showsGrid ? HarborStyle.chipIn : HarborStyle.chromeOut, value: session.showsGrid)
                        .transition(.opacity)
                        .allowsHitTesting(session.showsGrid)
                }
            }
        }
    }

    private func header(_ content: HarborDisplayContent) -> some View {
        VStack(spacing: 14) {
            HarborSearchField(session: session)
            if !session.access.windows {
                HarborAccessNotice {
                    intents.prepareSettings()
                    openWindow.openDockSettings()
                }
            }
        }
        .frame(width: content.size.width)
        .padding(.top, HarborStripMetrics.headerTop(edge: content.stripEdge))
        .opacity(session.showsBackdrop ? 1 : 0)
        .animation(session.showsBackdrop ? .easeOut(duration: 0.25) : HarborStyle.chromeOut, value: session.showsBackdrop)
        .scaleEffect(session.showsBackdrop || session.reduceMotion ? 1 : 0.96)
        .offset(y: session.showsBackdrop || session.reduceMotion ? 0 : -16)
        .animation(session.showsBackdrop ? HarborStyle.headerIn : HarborStyle.chromeOut, value: session.showsBackdrop)
        .allowsHitTesting(session.showsGrid)
    }

    @ViewBuilder
    private func emptyState(_ content: HarborDisplayContent) -> some View {
        if session.showsGrid, content.shownGroups.isEmpty {
            HarborEmptyState(query: session.query)
                .frame(width: content.size.width, height: content.size.height * 0.88, alignment: .center)
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.15)))
        }
    }

    private func strip(_ content: HarborDisplayContent) -> some View {
        let counts = Dictionary(content.groups.map { ($0.id, $0.count) }, uniquingKeysWith: +)
        return HarborDockStrip(apps: content.stripApps, counts: counts, icons: session.icons, edge: content.stripEdge,
                               displaySize: content.size, seed: content.dockSeed, filter: session.appFilter,
                               transformed: session.showsBackdrop, reduceMotion: session.reduceMotion,
                               reduceTransparency: session.reduceTransparency,
                               tap: { appID in intents.stripTapped(appID, displayID: displayID) },
                               closeHarbor: { intents.dismiss() })
            .allowsHitTesting(session.showsGrid)
    }

    // MARK: Window placement

    /// A window's place for the current phase.
    private struct Tile {
        let window: HarborWindow
        let rect: CGRect
        let visible: Bool
        let zIndex: Double
    }

    private func tiles(_ content: HarborDisplayContent) -> [Tile] {
        let shown = content.shownGroups.flatMap(\.windows)
        switch session.phase {
        case .open:
            return shown.compactMap { window in
                guard let rect = content.layout.windows[window.id] else { return nil }
                return Tile(window: window, rect: rect, visible: true,
                            zIndex: session.hovered == window.id || session.selected == window.id ? 1 : 0)
            }
        case .entering, .leaving, .hidden:
            return shown.compactMap { window in
                let flies = session.phase == .entering ? session.thumbnails[window.id] != nil
                    : session.flying.contains(window.id)
                let grid = content.layout.windows[window.id]
                if flies {
                    let lifted = session.raisedWindowID == window.id
                    return Tile(window: window, rect: content.desktopFrame(of: window), visible: true,
                                zIndex: lifted ? 10_000 : -Double(window.stackOrder))
                }
                guard let grid else { return nil }
                return Tile(window: window, rect: grid, visible: false, zIndex: -Double(window.stackOrder))
            }
        }
    }
}

#if DEBUG
#Preview("Harbor, typical") {
    HarborPreviewHost(scenario: .typical)
}

#Preview("Harbor, many windows") {
    HarborPreviewHost(scenario: .many)
}

#Preview("Harbor, crowded (scrolls)") {
    HarborPreviewHost(scenario: .crowded)
}

#Preview("Harbor, no Accessibility") {
    HarborPreviewHost(scenario: .noAccessibility)
}

#Preview("Harbor, empty") {
    HarborPreviewHost(scenario: .empty)
}

#Preview("Harbor, Reduce Transparency") {
    HarborPreviewHost(scenario: .typical, reduceTransparency: true)
}
#endif
