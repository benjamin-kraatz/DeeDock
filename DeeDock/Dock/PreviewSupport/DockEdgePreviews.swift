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
    DockPreviewContent(dragProposal: DockDragProposal(pins: [.application(DockPreviewData.items[0].reference)], index: 3),
                       dragMessage: .dragPinHere, settings: DockSettings(edge: .right))
}

#Preview("Side error") {
    DockPreviewContent(errorMessage: .errorOpenApp(appName: "Sample Application", details: "Sample launch failure"),
                       settings: DockSettings(edge: .left))
}
#Preview("Top dock, magnified with long labels") {
    DockPreviewContent(items: DockPreviewData.longNameItems, magnified: true, settings: DockSettings(edge: .top))
}

#Preview("Top overflow, reduced motion and transparency") {
    DockPreviewContent(items: DockPreviewData.crowdedItems, reduceMotion: true, reduceTransparency: true,
                       settings: DockSettings(edge: .top), availableLength: 400)
        .preferredColorScheme(.dark)
}

#Preview("Top insertion gap") {
    DockPreviewContent(dragProposal: DockDragProposal(pins: [.application(DockPreviewData.items[0].reference)], index: 3),
                       dragMessage: .dragPinHere, settings: DockSettings(edge: .top))
}

#Preview("Top error") {
    DockPreviewContent(errorMessage: .errorOpenApp(appName: "Sample Application", details: "Sample launch failure"),
                       settings: DockSettings(edge: .top))
}

#Preview("Empty top dock") {
    DockPreviewContent(items: [], settings: DockSettings(edge: .top))
}
#endif
