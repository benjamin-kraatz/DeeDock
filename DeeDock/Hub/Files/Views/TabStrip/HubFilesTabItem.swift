import SwiftUI

/// One browser tab: folder icon and name, a close button on hover, and an accent underline when
/// selected. It is also a drop target, and resting on it during a drag switches to it.
struct HubFilesTabItem: View {
    let model: HubFilesModel
    let tab: HubFilesBrowserTab
    /// The strip's namespace for the sliding selection (fill and underline).
    let selectedTab: Namespace.ID

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    private var theme: HubFilesTheme { HubFilesTheme(scheme) }
    private var isSelected: Bool { model.selectedTabID == tab.id }
    private var isDropTarget: Bool { model.dropHighlight == .tab(tab.id) }
    private var title: String { model.title(for: tab) }

    var body: some View {
        HStack(spacing: 8) {
            HubFilesFolderIcon(url: tab.activePane.folderURL ?? model.home, size: 16)
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 16, height: 16)
        }
        .font(.system(size: 13))
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(minWidth: 120, maxWidth: 200, minHeight: HubFilesMetrics.tabHeight, maxHeight: HubFilesMetrics.tabHeight)
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: HubStyle.rowRadius, topTrailingRadius: HubStyle.rowRadius)
            if isDropTarget {
                shape.fill(theme.accentSelection)
            } else if isSelected {
                shape.fill(theme.selection)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color.accentColor).frame(height: 2.5).padding(.horizontal, 10)
                    }
                    .matchedGeometryEffect(id: "selected", in: selectedTab)
            } else if hovered {
                shape.fill(theme.chip)
            }
        }
        .overlay {
            HubFilesInteractionRegion(
                interaction: HubFilesInteractions.tab(tab, model: model) { hovered = $0 },
                model: model)
        }
        .overlay(alignment: .trailing) {
            if model.tabs.count > 1 {
                HubFilesTabCloseButton { model.closeTab(tab.id) }
                    .padding(.trailing, 12)
                    .opacity(hovered ? 1 : 0)
            }
        }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: hovered)
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.15)), value: isDropTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selectTab(tab.id) }
        .accessibilityAction(named: Text(.hubFilesCloseTab)) { model.closeTab(tab.id) }
    }
}

/// The small × that closes a tab.
private struct HubFilesTabCloseButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(hovered ? HubFilesTheme(scheme).chipHighlight : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(Text(.hubFilesCloseTab))
        .accessibilityLabel(Text(.hubFilesCloseTab))
    }
}
