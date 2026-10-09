import SwiftUI

/// The selected browser tab's panes, side by side when split.
struct HubFilesPanes: View {
    let model: HubFilesModel
    let tab: HubFilesBrowserTab

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tab.visiblePanes.enumerated()), id: \.element.id) { index, pane in
                if index > 0 {
                    Rectangle().fill(HubFilesTheme(scheme).line).frame(width: 0.5)
                }
                HubFilesPaneView(model: model, tab: tab, pane: pane, index: index)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(HubFilesMotion.layout, value: tab.isSplit)
        .id(tab.id)
    }
}
