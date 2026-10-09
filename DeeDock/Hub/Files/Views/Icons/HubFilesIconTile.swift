import SwiftUI

/// A tile in icon view: a 54 pt thumbnail or icon, a two-line name, and a size or item count.
struct HubFilesIconTile: View {
    let context: HubFilesPaneContext
    let item: HubFileItem

    @State private var hovered = false
    @State private var childCount: Int?

    private var pane: HubFilesPane { context.pane }
    private var isSelected: Bool { pane.selection.contains(item.url) }
    private var isRenaming: Bool { pane.isRenaming(item) }

    private var caption: String {
        if item.isDirectory { return childCount.map(HubFilesFormatting.itemCount) ?? " " }
        return HubFilesFormatting.size(item.byteSize)
    }

    var body: some View {
        VStack(spacing: 6) {
            HubFilesItemIcon(item: item, size: HubFilesMetrics.tileIconSize, thumbnail: true)
                .hubFilesQuickLookSource(item.url, quickLook: context.model.quickLook)
            if isRenaming {
                HubFilesRenameField(model: context.model, pane: pane, isDirectory: item.isDirectory, alignment: .center)
                    .frame(maxWidth: 120)
            } else {
                Text(verbatim: item.name)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            Text(verbatim: caption)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 10, leading: 4, bottom: 8, trailing: 4))
        .frame(maxWidth: .infinity)
        .modifier(HubFilesItemBackground(
            shape: .rect(cornerRadius: 12),
            isSelected: isSelected, isActivePane: context.isActive, isHovered: hovered,
            isDropTarget: context.model.dropHighlight == .item(item.url), isFresh: pane.isFresh(item)))
        .padding(2)
        .overlay {
            if !isRenaming {
                HubFilesInteractionRegion(
                    interaction: HubFilesInteractions.item(item, pane: pane, paneIndex: context.index,
                                                           model: context.model) { hovered = $0 },
                    model: context.model)
            }
        }
        .task(id: item.isDirectory ? item.url : nil) {
            guard item.isDirectory else { return }
            childCount = await context.model.dataSource.itemCount(in: item.url)
        }
        .modifier(HubFilesItemAccessibility(item: item, isSelected: isSelected, detail: caption,
                                            model: context.model, pane: pane))
    }
}
