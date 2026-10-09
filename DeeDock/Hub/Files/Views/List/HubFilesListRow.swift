import SwiftUI

/// A 32 pt list row: icon and name, date modified, kind (unsplit), and size.
struct HubFilesListRow: View {
    let context: HubFilesPaneContext
    let item: HubFileItem

    @State private var hovered = false

    private var pane: HubFilesPane { context.pane }
    private var isSelected: Bool { pane.selection.contains(item.url) }
    private var isRenaming: Bool { pane.isRenaming(item) }
    private var date: String { HubFilesFormatting.date(item.modified) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                HubFilesItemIcon(item: item, size: 22)
                    .hubFilesQuickLookSource(item.url, quickLook: context.model.quickLook)
                if isRenaming {
                    HubFilesRenameField(model: context.model, pane: pane, isDirectory: item.isDirectory)
                } else {
                    Text(verbatim: item.name)
                        .font(.system(size: 13.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            detail(date).frame(width: HubFilesMetrics.modifiedColumnWidth, alignment: .leading)
            if context.showsKind {
                detail(item.isDirectory ? String(localized: .hubFilesKindFolder) : item.kindDescription)
                    .padding(.leading, 14)
                    .frame(width: HubFilesMetrics.kindColumnWidth, alignment: .leading)
            }
            detail(HubFilesFormatting.size(item.byteSize))
                .frame(width: HubFilesMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: HubFilesMetrics.rowHeight)
        .modifier(HubFilesItemBackground(
            shape: .rect(cornerRadius: HubStyle.rowRadius),
            isSelected: isSelected, isActivePane: context.isActive, isHovered: hovered,
            isDropTarget: context.model.dropHighlight == .item(item.url), isFresh: pane.isFresh(item)))
        .overlay {
            if !isRenaming {
                HubFilesInteractionRegion(
                    interaction: HubFilesInteractions.item(item, pane: pane, paneIndex: context.index,
                                                           model: context.model) { hovered = $0 },
                    model: context.model)
            }
        }
        .modifier(HubFilesItemAccessibility(item: item, isSelected: isSelected, detail: date,
                                            model: context.model, pane: pane))
    }

    private func detail(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
