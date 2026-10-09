import SwiftUI

/// One column of column view. The item on the path to the current folder keeps a gray
/// highlight; the column's empty area accepts drops into its folder.
struct HubFilesColumn: View {
    let context: HubFilesPaneContext
    /// The column's folder, or nil for the single Recents column.
    let folder: URL?
    let items: [HubFileItem]
    /// The next folder on the path, highlighted in this column.
    let pathChild: URL?

    @Environment(\.colorScheme) private var scheme

    private var isDropTarget: Bool { folder.map { context.model.dropHighlight == .column($0) } ?? false }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        HubFilesColumnItem(context: context, item: item, column: folder,
                                           isOnPath: pathChild.map { HubFilesPath.same($0, item.url) } ?? false)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                .background {
                    if let folder {
                        HubFilesInteractionRegion(
                            interaction: HubFilesInteractions.columnBackground(folder, pane: context.pane,
                                                                               paneIndex: context.index, model: context.model),
                            model: context.model)
                    }
                }
            }
        }
        .frame(width: HubFilesMetrics.columnWidth)
        .background(isDropTarget ? HubFilesTheme(scheme).accentSelection.opacity(0.5) : .clear)
        .overlay(alignment: .trailing) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(width: 0.5)
        }
        .animation(HubFilesMotion.quick, value: isDropTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: folder.map(context.model.displayName(for:)) ?? String(localized: .hubFilesPlaceRecents)))
    }
}

/// A 28 pt item in a column, with a chevron for folders.
private struct HubFilesColumnItem: View {
    let context: HubFilesPaneContext
    let item: HubFileItem
    let column: URL?
    let isOnPath: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    private var isSelected: Bool { context.pane.selection.contains(item.url) }
    private var isRenaming: Bool { context.pane.isRenaming(item) }

    var body: some View {
        HStack(spacing: 8) {
            HubFilesItemIcon(item: item, size: 18)
                .hubFilesQuickLookSource(item.url, quickLook: context.model.quickLook)
            if isRenaming {
                // Same inline field as list rows and icon tiles; the interaction region below is
                // removed meanwhile so clicks reach the text field.
                HubFilesRenameField(model: context.model, pane: context.pane, isDirectory: item.isDirectory,
                                    width: nil)
            } else {
                Text(verbatim: item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: HubFilesMetrics.columnRowHeight)
        .background(isOnPath && !isSelected ? HubFilesTheme(scheme).selection : .clear, in: .rect(cornerRadius: 7))
        .modifier(HubFilesItemBackground(
            shape: .rect(cornerRadius: 7),
            isSelected: isSelected, isActivePane: context.isActive, isHovered: hovered && !isOnPath,
            isDropTarget: context.model.dropHighlight == .item(item.url), isFresh: context.pane.isFresh(item)))
        .overlay {
            if !isRenaming {
                HubFilesInteractionRegion(interaction: interaction, model: context.model)
            }
        }
        .modifier(HubFilesItemAccessibility(item: item, isSelected: isSelected || isOnPath,
                                            detail: HubFilesFormatting.date(item.modified),
                                            model: context.model, pane: context.pane))
    }

    private var interaction: HubFilesInteraction {
        if let column {
            return HubFilesInteractions.columnItem(item, column: column, pane: context.pane, paneIndex: context.index,
                                                   model: context.model) { hovered = $0 }
        }
        return HubFilesInteractions.item(item, pane: context.pane, paneIndex: context.index,
                                         model: context.model) { hovered = $0 }
    }
}
