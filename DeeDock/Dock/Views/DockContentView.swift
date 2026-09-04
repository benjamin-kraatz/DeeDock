import SwiftUI

/// Owns scrolling and hover state. Geometry and actions come from the panel; previews stay inert.
struct DockContentView: View {
    let items: [DockItem]
    var entries: [DockRenderSlot]? = nil
    let launchingIDs: Set<String>
    let selectedTarget: DockEntryID?
    let keyboardFocus: Bool
    let errorMessage: LocalizedStringResource?
    let interaction: DockInteraction
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let primaryAppAction: (DockItem) -> Void
    let openApp: (DockItem) -> Void
    let togglePin: (DockItem) -> Void
    let dismissError: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var hoveredID: DockEntryID?
    private var layout: DockGeometry.Layout { interaction.layout }
    private var slots: [DockRenderSlot] { DockRenderSlot.slots(entries: entries ?? items.map(DockRenderSlot.app), proposal: interaction.dragProposal) }
    private var sizes: [CGFloat] {
        layout.sizes(pointerAlong: interaction.dragActive ? nil : interaction.pointer.map {
            layout.edge.along($0) - scrollOffset
        }, reduceMotion: reduceMotion)
    }
    private var viewport: CGRect { CGRect(origin: .zero, size: layout.viewportSize) }
    private func shifted(_ rect: CGRect, by offset: CGFloat) -> CGRect {
        rect.offsetBy(dx: layout.edge.isVertical ? 0 : offset, dy: layout.edge.isVertical ? offset : 0)
    }
    private var viewportSurface: CGRect {
        shifted(layout.surfaceFrame(sizes: sizes), by: scrollOffset).intersection(viewport)
    }

    var body: some View {
        let edge = layout.edge
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView(edge.isVertical ? .vertical : .horizontal) {
                    DockSurfaceView(slots: slots, launchingIDs: launchingIDs, selectedTarget: selectedTarget,
                        keyboardFocus: keyboardFocus, showsLabel: errorMessage == nil && !interaction.dragActive,
                        layout: layout, sizes: sizes, surface: layout.surfaceFrame(sizes: sizes),
                        viewport: shifted(viewport, by: -scrollOffset), hoveredID: $hoveredID,
                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                        primaryAppAction: primaryAppAction, openApp: openApp,
                        togglePin: togglePin, interaction: interaction,
                        iconFrameChanged: { id, rect in
                            guard interaction.layout.edge == edge else { return }
                            interaction.setIconRect(rect?.intersection(viewport), for: id)
                        }, menuTracking: { interaction.menuTrackingChanged?($0) },
                        accessibilityFocus: { interaction.accessibilityFocusChanged?($0, $1) })
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        edge.along(geometry.frame(in: .named("dockViewport")).origin)
                    } action: { value in
                        guard interaction.layout.edge == edge else { return }
                        guard scrollOffset != value || interaction.scrollOffset != value else { return }
                        scrollOffset = value; interaction.scrollOffset = value
                        interaction.scrollChanged?()
                    }
                }
                .scrollPosition($scrollPosition)
                .onChange(of: interaction.scrollRequest) { previous, current in
                    let offset = min(max(0, -scrollOffset + current - previous), max(0, layout.canvasLength - layout.viewportLength))
                    if edge.isVertical { scrollPosition.scrollTo(y: offset) }
                    else { scrollPosition.scrollTo(x: offset) }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .coordinateSpace(name: "dockViewport")
                .onAppear {
                    // Axis changes recreate only presentation. Store selection remains stable.
                    if keyboardFocus, let selectedTarget { proxy.scrollTo(selectedTarget.hitID, anchor: .center) }
                }
                .onChange(of: selectedTarget) { _, id in
                    if let id {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            proxy.scrollTo(id.hitID, anchor: .center)
                        }
                    }
                }
            }
            DockCalloutsView(errorMessage: errorMessage, dragMessage: interaction.dragMessage,
                layout: layout, interaction: interaction, dismissError: dismissError)
        }
        .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
        .coordinateSpace(name: "dockRoot")
        .clipped()
        .onAppear { interaction.surfaceRect = viewportSurface }
        .onChange(of: viewportSurface) { _, rect in
            guard interaction.layout.edge == edge else { return }
            interaction.surfaceRect = rect
        }
        .onChange(of: layout.canvasLength) { _, _ in
            let offset = min(max(0, -scrollOffset), max(0, layout.canvasLength - layout.viewportLength))
            if edge.isVertical { scrollPosition.scrollTo(y: offset) } else { scrollPosition.scrollTo(x: offset) }
        }
        .onChange(of: layout.edge) { _, _ in hoveredID = nil }
        .onChange(of: interaction.pointer == nil) { _, outside in if outside { hoveredID = nil } }
        .onChange(of: slots.compactMap(\.target)) { _, ids in
            if let hoveredID, !ids.contains(hoveredID) { self.hoveredID = nil }
        }
        .onChange(of: hoveredID) { _, target in
            guard case .app(let id) = target,
                  let item = slots.compactMap(\.item).first(where: { $0.id == id }) else {
                interaction.windowPeekHoverChanged?(nil)
                return
            }
            interaction.windowPeekHoverChanged?(item)
        }
        .onDisappear { interaction.windowPeekHoverChanged?(nil) }
    }
}

#if DEBUG
    #Preview("Drag: live insertion gap") {
        DockPreviewContent(
            dragProposal: DockDragProposal(
                pins: [.application(DockPreviewData.items[0].reference)],
                index: 3
            ),
            dragMessage: .dragPinHere
        )
    }

    #Preview("Drag: empty dock with incoming apps") {
        DockPreviewContent(
            items: [],
            reduceMotion: true,
            reduceTransparency: true,
            dragProposal: DockDragProposal(
                pins: Array(DockPreviewData.items.prefix(2)).map { .application($0.reference) },
                index: 0
            ),
            dragMessage: .dragPinHere
        )
    }

    #Preview("Drag: rejected batch") {
        DockPreviewContent(dragMessage: .dragRejected)
    }

    #Preview("Pinned and running") {
        DockPreviewContent()
    }

    #Preview("Dark, reduced transparency and motion") {
        DockPreviewContent(reduceMotion: true, reduceTransparency: true)
            .preferredColorScheme(.dark)
    }

    #Preview("Magnified icons above fixed glass") {
        DockPreviewContent(magnified: true)
    }

    #Preview("Maximum icon size and magnification") {
        DockPreviewContent(
            magnified: true,
            settings: DockSettings(iconSize: 96, magnification: 2, itemSpacing: 4)
        )
    }

    #Preview("Empty") {
        DockPreviewContent(items: [])
    }

    #Preview("Launch error") {
        DockPreviewContent(
            errorMessage: .errorOpenApp(
                appName: "Sample App",
                details: "Sample launch failure"
            )
        )
    }
#endif
