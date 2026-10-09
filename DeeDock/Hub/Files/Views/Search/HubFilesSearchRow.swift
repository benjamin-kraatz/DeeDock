import SwiftUI

/// One search result: icon and highlighted name, Where (with ~ for home), date, and size.
struct HubFilesSearchRow: View {
    let model: HubFilesModel
    let item: HubFileItem

    @State private var hovered = false

    private var isSelected: Bool { model.searchSelection.contains(item.url) }
    private var date: String { HubFilesFormatting.date(item.modified) }
    private var location: String {
        HubFilesPath.parent(of: item.url).map { HubFilesPath.abbreviated($0, home: model.home) } ?? "/"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                HubFilesItemIcon(item: item, size: 22)
                    .hubFilesQuickLookSource(item.url, quickLook: model.quickLook)
                Text(HubFilesMatchHighlight.attributed(item.name, query: model.trimmedQuery))
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: location)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: HubFilesMetrics.whereColumnWidth, alignment: .leading)
            detail(date).frame(width: HubFilesMetrics.modifiedColumnWidth, alignment: .leading)
            detail(HubFilesFormatting.size(item.byteSize)).frame(width: HubFilesMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: HubFilesMetrics.rowHeight)
        .modifier(HubFilesItemBackground(
            shape: .rect(cornerRadius: HubStyle.rowRadius),
            isSelected: isSelected, isActivePane: true, isHovered: hovered,
            isDropTarget: model.dropHighlight == .item(item.url), isFresh: false))
        .overlay {
            HubFilesInteractionRegion(interaction: HubFilesInteractions.searchResult(item, model: model) { hovered = $0 },
                                      model: model)
        }
        .modifier(HubFilesItemAccessibility(item: item, isSelected: isSelected, detail: "\(location), \(date)",
                                            model: model, pane: nil))
    }

    private func detail(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Marks the first case- and diacritic-insensitive match of the query in a name.
enum HubFilesMatchHighlight {
    static func attributed(_ name: String, query: String) -> AttributedString {
        var text = AttributedString(name)
        guard !query.isEmpty,
              let range = name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
              let lower = AttributedString.Index(range.lowerBound, within: text),
              let upper = AttributedString.Index(range.upperBound, within: text) else { return text }
        text[lower..<upper].backgroundColor = Color.accentColor.opacity(0.35)
        return text
    }
}
