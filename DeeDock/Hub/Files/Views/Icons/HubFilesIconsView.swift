import SwiftUI

/// Icon view: an adaptive grid of tiles at least 96 pt wide. Reports its column count to the
/// pane so arrow keys move by row.
struct HubFilesIconsView: View {
    let context: HubFilesPaneContext

    private static let spacing: CGFloat = 6
    private static let horizontalPadding: CGFloat = 10

    var body: some View {
        HubFilesPaneScroll(context: context) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: HubFilesMetrics.tileMinimumWidth), spacing: Self.spacing)],
                      spacing: Self.spacing) {
                ForEach(context.pane.items) { item in
                    HubFilesIconTile(context: context, item: item)
                        .id(item.url)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .padding(EdgeInsets(top: 10, leading: Self.horizontalPadding, bottom: 10, trailing: Self.horizontalPadding))
            .animation(HubFilesMotion.animation(.easeOut(duration: 0.26)), value: context.pane.items.map(\.url))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            // Mirrors the adaptive grid's packing: as many minimum-width tiles as fit with spacing.
            let usable = width - Self.horizontalPadding * 2 + Self.spacing
            context.pane.iconColumns = max(1, Int(usable / (HubFilesMetrics.tileMinimumWidth + Self.spacing)))
        }
    }
}
