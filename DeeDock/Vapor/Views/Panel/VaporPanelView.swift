import SwiftUI

/// The panel that opens beside the orb: header, the Finder-access offer, Finder suggestions,
/// folder rows, drop zone and the hold-to-delete footer.
///
/// ``VaporPanelStage`` hosts it inside a larger window and grows it out of the orb. During a
/// delete the stage passes the folders as they were (`pull`) and where the orb is
/// (`pullTarget`), so the rows can fly into the orb after staging has already removed them.
struct VaporPanelView: View {
    let controller: VaporController
    var pull: VaporDeletion?
    var pullTarget: CGPoint?

    static let width: CGFloat = 390

    var body: some View {
        let folders = pull?.folders ?? controller.folders
        let reduceMotion = controller.reduceMotion
        VStack(alignment: .leading, spacing: 0) {
            VaporPanelHeader(totals: VaporTotals(folders), clear: controller.clear)
            if controller.offersFinderAccess, pull == nil {
                VaporFinderAccessRow { controller.requestFinderAccess?() }
                    .transition(.opacity)
            }
            if !controller.suggestions.isEmpty, pull == nil {
                VaporFoundInSection(folderName: controller.finderFolder?.lastPathComponent ?? "",
                                    suggestions: controller.suggestions, reduceMotion: reduceMotion,
                                    add: controller.addSuggestion, addAll: { controller.addAllSuggestions() })
                    .transition(.opacity)
            }
            if folders.isEmpty {
                VaporPanelEmptyState()
            } else {
                VaporFolderList(folders: folders, home: controller.home, reduceMotion: reduceMotion,
                                pullTarget: pullTarget, remove: controller.remove)
                VaporDropZone(isTargeted: controller.dropHover.isOverPanel)
            }
            if !folders.isEmpty {
                VaporPanelFooter(controller: controller, folders: folders)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .frame(width: Self.width)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: folders.isEmpty)
        .animation(.easeOut(duration: 0.2), value: controller.suggestions.isEmpty)
        .vaporGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous),
                    reduceTransparency: controller.reduceTransparency)
    }
}

#if DEBUG
#Preview("Empty, Finder access undecided") {
    VaporPanelView(controller: VaporPreviewData.controller(panel: true, permission: .undetermined))
        .padding(40)
        .background(VaporPreviewBackdrop())
}

#Preview("Mixed, calculating, failure, Found in, hold half way") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.panel, panel: true,
                                                           suggestions: Array(VaporPreviewData.suggestions.prefix(2)),
                                                           hold: .frozen(at: 0.5)))
        .padding(40)
        .background(VaporPreviewBackdrop())
}

#Preview("Mixed known and unknown, light") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true))
        .padding(40)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.light)
}

#Preview("Long German labels, dark") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true))
        .padding(40)
        .background(VaporPreviewBackdrop())
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Reduce Transparency, dark") {
    VaporPanelView(controller: VaporPreviewData.controller(VaporPreviewData.mixed, panel: true, reduceTransparency: true))
        .padding(40)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.dark)
}
#endif
