#if DEBUG
import SwiftUI

#Preview("Left dock, magnified") {
    DockPreviewContent(magnified: true, settings: DockSettings(edge: .left))
}

#Preview("Right dock, dark and reduced transparency") {
    DockPreviewContent(reduceMotion: true, reduceTransparency: true, settings: DockSettings(edge: .right))
        .preferredColorScheme(.dark)
}

#Preview("Side overflow") {
    DockPreviewContent(items: DockPreviewData.crowdedItems, settings: DockSettings(edge: .left), availableLength: 400)
}

#Preview("Long name beside right dock") {
    DockPreviewContent(items: DockPreviewData.longNameItems, settings: DockSettings(edge: .right))
}

#Preview("Empty left dock") {
    DockPreviewContent(items: [], settings: DockSettings(edge: .left))
}

#Preview("Side insertion gap") {
    DockPreviewContent(dragProposal: DockDragProposal(references: [DockPreviewData.items[0].reference], index: 3),
                       dragMessage: .dragPinHere, settings: DockSettings(edge: .right))
}

#Preview("Side error") {
    DockPreviewContent(errorMessage: .errorOpenApp(appName: "Sample Application", details: "Sample launch failure"),
                       settings: DockSettings(edge: .left))
}
#endif
