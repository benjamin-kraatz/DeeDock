import SwiftUI

/// Owns viewport scrolling and hover state while rendering supplied app snapshots.
///
/// Actions are injected so previews never launch applications or write preferences.
/// `interaction` exchanges panel-local geometry with the AppKit window controller.
struct DockContentView: View {
    let items: [DockItem]
    let launchingIDs: Set<String>
    let selectedID: String?
    let keyboardFocus: Bool
    let errorMessage: LocalizedStringResource?
    let interaction: DockInteraction
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let openApp: (DockItem) -> Void
    let togglePin: (DockItem) -> Void
    let dismissError: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var hoveredID: String?

    private var layout: DockGeometry.Layout { interaction.layout }
    private var sizes: [CGFloat] {
        // Convert viewport coordinates to the resting canvas, not the animated icon positions.
        layout.sizes(pointerX: interaction.pointer.map { $0.x - scrollOffset }, reduceMotion: reduceMotion)
    }
    private var surface: CGRect { layout.surfaceFrame(sizes: sizes) }
    private var viewport: CGRect {
        CGRect(x: 0, y: 0, width: layout.viewportWidth, height: DockGeometry.panelHeight)
    }
    private var viewportSurface: CGRect {
        surface.offsetBy(dx: scrollOffset, dy: 0).intersection(
            viewport)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    DockSurfaceView(
                        items: items, launchingIDs: launchingIDs, selectedID: selectedID,
                        keyboardFocus: keyboardFocus, showsLabel: errorMessage == nil,
                        layout: layout, sizes: sizes, surface: surface, hoveredID: $hoveredID,
                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                        openApp: openApp, togglePin: togglePin,
                        iconFrameChanged: { id, rect in
                            interaction.setIconRect(rect?.intersection(viewport), for: id)
                        }
                    )
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .named("dockViewport")).minX
                    } action: { scrollOffset = $0 }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .coordinateSpace(name: "dockViewport")
                .onChange(of: selectedID) { _, id in
                    if let id {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            if let errorMessage {
                DockErrorBanner(message: errorMessage, maximumWidth: min(420, layout.viewportWidth - 16),
                                dismiss: dismissError)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dockRoot")) } action: {
                        interaction.errorRect = $0
                    }
                    .onDisappear { interaction.errorRect = .zero }
            }
        }
        .frame(width: layout.viewportWidth, height: DockGeometry.panelHeight)
        .coordinateSpace(name: "dockRoot")
        .clipped()
        // Report only painted interactive regions. Transparent panel margins must pass clicks through.
        .onAppear { interaction.surfaceRect = viewportSurface }
        .onChange(of: viewportSurface) { _, rect in interaction.surfaceRect = rect }
        .onChange(of: interaction.pointer) { _, point in if point == nil { hoveredID = nil } }
        .onChange(of: items.map(\.id)) { _, ids in
            if let hoveredID, !ids.contains(hoveredID) { self.hoveredID = nil }
        }
    }
}

#if DEBUG
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

#Preview("Empty") {
    DockPreviewContent(items: [])
}

#Preview("Launch error") {
    DockPreviewContent(errorMessage: .errorOpenApp(appName: "Sample App", details: "Sample launch failure"))
}
#endif
