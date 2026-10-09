import SwiftUI

/// The sortable column header of list view: Name, Date Modified, Kind (unsplit only), Size.
///
/// Clicking the sorted column flips its direction; clicking another sorts by it, ascending for
/// Name and Kind and newest or largest first for Date Modified and Size, as in the mockup.
struct HubFilesListHeader: View {
    let pane: HubFilesPane
    let showsKind: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            column(.name, .hubFilesColumnName).frame(maxWidth: .infinity, alignment: .leading)
            column(.modified, .hubFilesColumnModified).frame(width: HubFilesMetrics.modifiedColumnWidth, alignment: .leading)
            if showsKind {
                column(.kind, .hubFilesColumnKind)
                    .padding(.leading, 14)
                    .frame(width: HubFilesMetrics.kindColumnWidth, alignment: .leading)
            }
            column(.size, .hubFilesColumnSize).frame(width: HubFilesMetrics.sizeColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: HubFilesMetrics.listHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
        }
        .padding(.horizontal, 10)
    }

    private func column(_ key: HubFileSortKey, _ title: LocalizedStringResource) -> some View {
        HubFilesSortHeaderButton(title: title, isSorted: pane.sort.key == key, ascending: pane.sort.ascending) {
            if pane.sort.key == key {
                pane.sort.ascending.toggle()
            } else {
                pane.sort = HubFileSort(key: key, ascending: key == .name || key == .kind)
            }
        }
    }
}

/// One header title with a direction arrow while sorted.
private struct HubFilesSortHeaderButton: View {
    let title: LocalizedStringResource
    let isSorted: Bool
    let ascending: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: isSorted ? .medium : .regular))
                    .lineLimit(1)
                if isSorted {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 5.5))
                        .rotationEffect(.degrees(ascending ? 0 : 180))
                }
            }
            .foregroundStyle(isSorted || hovered ? .primary : .secondary)
            .padding(.trailing, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(HubFilesMotion.quick, value: ascending)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isSorted ? Text(ascending ? .hubFilesSortAscending : .hubFilesSortDescending) : Text(verbatim: ""))
        .accessibilityAddTraits(isSorted ? [.isButton, .isSelected] : .isButton)
    }
}
