import SwiftUI

/// Keeps messages upright inside the inward envelope. Only errors receive mouse input.
struct DockCalloutsView: View {
    let errorMessage: LocalizedStringResource?
    let dragMessage: LocalizedStringResource?
    let layout: DockGeometry.Layout
    let interaction: DockInteraction
    let dismissError: () -> Void

    var body: some View {
        let region = layout.edge == .bottom && errorMessage != nil
            ? CGRect(origin: .zero, size: layout.viewportSize)
            : layout.calloutRegion(size: layout.iconSize * layout.magnification, length: layout.viewportLength)
        Group {
            if let errorMessage {
                DockErrorBanner(message: errorMessage, maximumWidth: min(420, max(1, region.width - 16)), dismiss: dismissError)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dockRoot")) } action: {
                        guard interaction.layout.edge == layout.edge else { return }
                        interaction.errorRect = $0.intersection(region)
                    }
                    .onDisappear {
                        guard interaction.layout.edge == layout.edge else { return }
                        interaction.errorRect = .zero
                    }
            } else if let dragMessage {
                DockDragFeedback(message: dragMessage)
                    .frame(maxWidth: max(1, region.width - 16))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: region.width, height: region.height, alignment: layout.edge.isVertical ? .center : .top)
        .clipped()
        .position(x: region.midX, y: region.midY)
    }
}
