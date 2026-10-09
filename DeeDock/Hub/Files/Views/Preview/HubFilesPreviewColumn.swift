import SwiftUI

/// The 272 pt preview column for the active pane's selection (or search selection).
///
/// One item: a Quick Look preview in a rounded well, its details, and Open, Quick Look, and
/// Reveal in Finder. Several: a fanned stack with the count and total size. None: the folder.
struct HubFilesPreviewColumn: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme

    private var selection: [HubFileItem] { model.actionableItems }

    var body: some View {
        let selection = selection
        VStack(alignment: .leading, spacing: 10) {
            Text(.hubFilesPreviewTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            well(selection)
                .frame(maxWidth: .infinity)
                .frame(height: HubFilesMetrics.previewWellHeight)
                .background(HubFilesTheme(scheme).well, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
                .clipShape(.rect(cornerRadius: 14))
                .id(selection.map(\.url))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            HubFilesPreviewDetails(model: model, selection: selection)
            if selection.count == 1 {
                HubFilesPreviewActions(model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: HubFilesMetrics.previewWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(width: 0.5)
        }
        .animation(HubFilesMotion.animation(.spring(response: 0.35, dampingFraction: 0.85)), value: selection.map(\.url))
    }

    @ViewBuilder
    private func well(_ selection: [HubFileItem]) -> some View {
        if selection.count > 1 {
            HubFilesPreviewStack(items: Array(selection.prefix(3)))
        } else if let item = selection.first {
            if item.isDirectory {
                HubFilesItemIcon(item: item, size: 128, thumbnail: true)
            } else {
                HubFilesQuickLookWell(item: item)
            }
        } else if let folder = model.isSearching ? nil : model.activePane.folderURL {
            HubFilesFolderIcon(url: folder, size: 128)
        }
    }
}

/// Fanned icons for a multiple selection, like the mockup's `.multi` stack.
private struct HubFilesPreviewStack: View {
    let items: [HubFileItem]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let step = CGFloat(index - (items.count == 1 ? 0 : 1))
                HubFilesItemIcon(item: item, size: 90, thumbnail: true)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .rotationEffect(.degrees(step * 7))
                    .offset(x: step * 12, y: step * -6)
            }
        }
        .frame(width: 110, height: 110)
    }
}

/// Name, kind and size, and modification date under the well.
private struct HubFilesPreviewDetails: View {
    let model: HubFilesModel
    let selection: [HubFileItem]

    @State private var childCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .textSelection(.enabled)
        .task(id: countedFolder) {
            childCount = nil
            guard let folder = countedFolder else { return }
            childCount = await model.dataSource.itemCount(in: folder)
        }
    }

    /// The folder whose items are counted: a single selected folder, or the shown folder.
    private var countedFolder: URL? {
        if selection.count == 1, let item = selection.first { return item.isDirectory ? item.url : nil }
        return selection.isEmpty && !model.isSearching ? model.activePane.folderURL : nil
    }

    private var title: String {
        if selection.count > 1 { return HubFilesFormatting.itemCount(selection.count) }
        if let item = selection.first { return item.name }
        return model.isSearching ? "" : model.displayName(for: model.activePane.location)
    }

    private var lines: [String] {
        if selection.count > 1 {
            let total = selection.compactMap(\.byteSize).reduce(0, +)
            return [HubFilesFormatting.size(total)]
        }
        let count = childCount.map(HubFilesFormatting.itemCount)
        guard let item = selection.first else {
            return count.map { [$0] } ?? []
        }
        let kind = item.isDirectory ? String(localized: .hubFilesKindFolder) : item.kindDescription
        let amount = item.isDirectory ? count : HubFilesFormatting.size(item.byteSize)
        return [[kind, amount].compactMap { $0 }.joined(separator: " · "),
                String(localized: .hubFilesPreviewModified(HubFilesFormatting.date(item.modified)))]
    }
}

/// Open (primary), Quick Look, and Reveal in Finder for a single selection.
private struct HubFilesPreviewActions: View {
    let model: HubFilesModel

    var body: some View {
        HStack(spacing: 6) {
            HubFilesPreviewButton(title: .hubFilesMenuOpen, isPrimary: true) { model.openSelection() }
            HubFilesPreviewButton(title: .hubFilesMenuQuickLook, isPrimary: false) { model.toggleQuickLook() }
            HubFilesPreviewButton(title: .hubFilesPreviewReveal, isPrimary: false) { model.revealSelectionInFinder() }
        }
    }
}

/// A compact rounded button in the preview column.
private struct HubFilesPreviewButton: View {
    let title: LocalizedStringResource
    let isPrimary: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let theme = HubFilesTheme(scheme)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isPrimary ? Color.accentColor : (hovered ? theme.chipHighlight : theme.chip),
                            in: .rect(cornerRadius: 8))
                .overlay {
                    if !isPrimary { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 0.5) }
                }
                .brightness(isPrimary && hovered ? 0.06 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.96))
        .onHover { hovered = $0 }
    }
}
