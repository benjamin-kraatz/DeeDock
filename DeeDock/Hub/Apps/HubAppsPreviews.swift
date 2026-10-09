#if DEBUG
import SwiftUI

/// The Apps tab at the anchored Hub's content size (panel height minus the header).
private struct HubAppsPreviewFrame: View {
    let model: HubAppsModel
    var width: CGFloat = HubStyle.anchoredSize.width

    var body: some View {
        HubAppsView(model: model)
            .frame(width: width, height: HubStyle.anchoredSize.height - HubStyle.headerHeight)
            .background(.regularMaterial)
    }
}

#Preview("Apps: suggestions and grid") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(suggested: true))
}

#Preview("Apps: suggestions, German, dark") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(suggested: true))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Apps: grid, light, narrow detached window") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(), width: HubStyle.minimumDetachedSize.width)
        .preferredColorScheme(.light)
}

#Preview("Apps: line icons, dark") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(lineIcons: true))
        .preferredColorScheme(.dark)
}

#Preview("Apps: list") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(suggested: true, list: true))
}

#Preview("Apps: grouped by category, German") {
    let model = HubAppsPreviewData.model()
    model.launcher.grouping = .category
    return HubAppsPreviewFrame(model: model)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Apps: no favorites (empty)") {
    let model = HubAppsPreviewData.model()
    model.launcher.filter = .favorites
    return HubAppsPreviewFrame(model: model)
}

#Preview("Apps: no apps discovered") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(names: []))
}

#Preview("Apps: search without results") {
    // Mixed search never ranks in the canvas, so a query shows the no-results state.
    HubAppsPreviewFrame(model: HubAppsPreviewData.model(query: "No matching app"))
}

#Preview("Apps: windows result type, dark") {
    let model = HubAppsPreviewData.model()
    model.launcher.search.kind = .window
    return HubAppsPreviewFrame(model: model)
        .preferredColorScheme(.dark)
}

#Preview("Apps: file actions") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.fileActionsModel())
}

#Preview("Apps: file actions, German, dark") {
    HubAppsPreviewFrame(model: HubAppsPreviewData.fileActionsModel())
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
