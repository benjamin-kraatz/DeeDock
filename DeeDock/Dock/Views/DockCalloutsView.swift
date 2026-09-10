import SwiftUI

/// Keeps messages upright inside the inward envelope. Only errors and the snap undo receive
/// mouse input; a failure must stay dismissable, so it outranks the undo offer.
struct DockCalloutsView: View {
    let errorMessage: LocalizedStringResource?
    /// Copy for the last gravity snap on this display, when one can still be undone.
    var undoMessage: LocalizedStringResource?
    let dragMessage: LocalizedStringResource?
    let layout: DockGeometry.Layout
    let interaction: DockInteraction
    let dismissError: () -> Void
    var undo: () -> Void = {}
    var dismissUndo: () -> Void = {}

    /// True for the two callouts that carry buttons, which the panel must report as clickable.
    private var claimsMouse: Bool { errorMessage != nil || undoMessage != nil }

    var body: some View {
        let region = !layout.edge.isVertical && claimsMouse
            ? CGRect(origin: .zero, size: layout.viewportSize)
            : layout.calloutRegion(size: layout.iconSize * layout.magnification, length: layout.viewportLength)
        Group {
            if let errorMessage {
                DockErrorBanner(message: errorMessage, maximumWidth: min(420, max(1, region.width - 16)), dismiss: dismissError)
                    .modifier(DockCalloutMouseRegion(region: region, layout: layout, interaction: interaction))
            } else if let undoMessage {
                StackGravityUndoBanner(message: undoMessage, maximumWidth: min(420, max(1, region.width - 16)),
                                       undo: undo, dismiss: dismissUndo)
                    .modifier(DockCalloutMouseRegion(region: region, layout: layout, interaction: interaction))
            } else if let dragMessage {
                DockDragFeedback(message: dragMessage)
                    .frame(maxWidth: max(1, region.width - 16))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: region.width, height: region.height, alignment: layout.edge.isVertical ? .center : (layout.edge == .top ? .bottom : .top))
        .clipped()
        .position(x: region.midX, y: region.midY)
    }
}

/// Reports a callout's on-screen rectangle so the panel lets the mouse reach its buttons.
///
/// Both button-bearing callouts share `errorRect`; only one of them is on screen at a time, and
/// the rectangle is cleared on disappear so a stale region cannot keep swallowing clicks.
private struct DockCalloutMouseRegion: ViewModifier {
    let region: CGRect
    let layout: DockGeometry.Layout
    let interaction: DockInteraction

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dockRoot")) } action: {
                guard interaction.layout.edge == layout.edge else { return }
                interaction.errorRect = $0.intersection(region)
            }
            .onDisappear {
                guard interaction.layout.edge == layout.edge else { return }
                interaction.errorRect = .zero
            }
    }
}
