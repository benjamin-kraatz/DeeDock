import SwiftUI

/// One pane: navigation bar and the listing in the tab's view mode.
///
/// In a split tab, only the active pane draws accent selections; the other uses gray, as in
/// Finder's inactive windows.
struct HubFilesPaneView: View {
    let model: HubFilesModel
    let tab: HubFilesBrowserTab
    let pane: HubFilesPane
    let index: Int

    @Environment(\.colorScheme) private var scheme

    private var isActive: Bool { !tab.isSplit || tab.activePaneIndex == index }
    private var isDropTarget: Bool { model.dropHighlight == .pane(pane.id) }

    var body: some View {
        VStack(spacing: 0) {
            HubFilesNavigationBar(model: model, pane: pane, index: index, isActive: isActive)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(isDropTarget ? Color.accentColor.opacity(0.08) : .clear)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HubFilesTheme(scheme).accentLine, lineWidth: 1.5)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .animation(HubFilesMotion.animation(.easeOut(duration: 0.2)), value: isDropTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.displayName(for: pane.location)))
    }

    @ViewBuilder
    private var content: some View {
        let context = HubFilesPaneContext(model: model, pane: pane, index: index, isActive: isActive,
                                          showsKind: !tab.isSplit)
        switch tab.viewMode {
        case .list: HubFilesListView(context: context)
        case .icons: HubFilesIconsView(context: context)
        case .columns: HubFilesColumnsView(context: context)
        }
    }
}

/// What a listing view needs to know about its pane.
struct HubFilesPaneContext {
    let model: HubFilesModel
    let pane: HubFilesPane
    let index: Int
    /// The pane receives keyboard input and draws accent selections.
    let isActive: Bool
    /// List view shows the Kind column (only when not split).
    let showsKind: Bool
}
