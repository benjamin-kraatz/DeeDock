#if DEBUG
import SwiftUI

#Preview("Collapsed sections on every edge") {
    ScrollView {
        VStack {
            ForEach(DockEdge.allCases, id: \.self) { edge in
                let settings = DockSettings(appVisibility: .collapsePinned, edge: edge)
                DockPreviewContent(settings: settings)
            }
        }
    }.frame(width: 700, height: 650)
}

#Preview("Expanded running apps, dark") {
    DockPreviewContent(settings: DockSettings(appVisibility: .collapseRunning, tooltipPreset: .spectrum), expanded: true)
        .preferredColorScheme(.dark)
}

#Preview("Zero pinned apps, reduced motion and transparency") {
    DockPreviewContent(items: [], reduceMotion: true, reduceTransparency: true,
                       settings: DockSettings(appVisibility: .collapsePinned, tooltipPreset: .nameCard))
}

#Preview("Long names and overflow") {
    DockPreviewContent(items: DockPreviewData.longNameItems + DockPreviewData.crowdedItems,
        settings: DockSettings(appVisibility: .collapsePinned, tooltipPreset: .nameCard), availableLength: 500, expanded: true)
}
#endif
