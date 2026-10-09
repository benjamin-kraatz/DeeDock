import SwiftUI

/// A Favorites entry: an accent SF Symbol and the place's name.
struct HubFilesSidebarRow: View {
    let model: HubFilesModel
    let place: HubFilesPlace
    /// The sidebar's namespace for the sliding current-location fill.
    let currentFill: Namespace.ID

    @State private var hovered = false

    private var location: HubFilesLocation { place.location(home: model.home) }
    private var title: String { place.title(home: model.home) }
    private var isCurrent: Bool { !model.isSearching && model.isCurrent(location) }
    private var isDropTarget: Bool {
        location.folderURL.map { model.dropHighlight == .sidebar($0) } ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: place.symbolName)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
            Text(verbatim: title)
                .font(.system(size: 13.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: HubFilesMetrics.rowHeight)
        .modifier(HubFilesSidebarItemBackground(isCurrent: isCurrent, isHovered: hovered, isDropTarget: isDropTarget,
                                                currentFill: currentFill))
        .overlay {
            HubFilesInteractionRegion(
                interaction: HubFilesInteractions.sidebar(location, model: model) { hovered = $0 },
                model: model)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.show(location) }
    }
}
