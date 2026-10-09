import SwiftUI

/// The Hub's Apps tab: notices, then file actions, mixed search results, or app browsing
/// (Suggested cards, the controls row, the app grid or list, and DOKK's tools).
///
/// The shell owns the panel, the header search field (bound to ``HubAppsModel/query``), focus, and
/// dismissal; keyboard navigation arrives through ``HubAppsModel/handleKeyDown(_:fromSearchField:)``.
struct HubAppsView: View {
    let model: HubAppsModel
    @State private var confirmClear = false

    /// - Parameter model: The app-wide Apps model the shell created.
    init(model: HubAppsModel) {
        self.model = model
    }

    private var launcher: LauncherState { model.launcher }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - HubAppsStyle.contentInsets.leading
                - HubAppsStyle.contentInsets.trailing
            let columns = HubAppsStyle.columns(forContentWidth: contentWidth)
            VStack(alignment: .leading, spacing: 0) {
                HubAppsStatusView(launcher: launcher, requestClearHistory: requestClearHistory)
                content(columns: columns)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .onChange(of: columns, initial: true) { _, columns in launcher.navigationColumns = columns }
        }
        .background { HubAppsWindowReader { model.hostWindow = $0 } }
        // Files dropped on the open tab start file actions, as a drop on the DOKK tile does.
        .modifier(HubAppsFileDrop(model: model))
        // A click anywhere in the results ends arrow-key navigation, like the old launcher.
        .simultaneousGesture(TapGesture().onEnded { model.clearKeyboardSelection() })
        .confirmationDialog(Text(.launcherClearHistory), isPresented: $confirmClear) {
            Button(role: .destructive) { launcher.history.clear() } label: { Text(.launcherClearHistory) }
        } message: { Text(.launcherClearHistoryDetail) }
        .onChange(of: confirmClear) { _, presented in model.setDialogPresented(presented) }
    }

    @ViewBuilder private func content(columns: Int) -> some View {
        if launcher.usesFileActions {
            VStack(alignment: .leading, spacing: 12) {
                controls
                LauncherFileInputSummaryView(state: launcher.fileActions)
                LauncherFileActionsView(launcher: launcher)
            }
            .padding(HubAppsStyle.contentInsets)
        } else if launcher.usesMixedResults {
            LauncherMixedResultsView(launcher: launcher) { controls }
        } else {
            let groups = launcher.groups
            let context = LauncherBrowseScroll.Context(state: launcher, columns: columns, groups: groups)
            LauncherResultsView(state: launcher, columns: columns, groups: groups,
                                appearedAt: model.appearedAt) { controls }
                .modifier(LauncherBrowseScrollRestoration(state: launcher, context: context))
                .id(context)
        }
    }

    private var controls: some View {
        HubAppsControlsRow(launcher: launcher, requestClearHistory: requestClearHistory)
    }

    private func requestClearHistory() { confirmClear = true }
}
