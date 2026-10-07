import SwiftUI

/// The Suggested row above the compact grid, using the grid's tiles and spacing.
///
/// Mirrors the full Launcher's Suggested section except for its survey card. The compact search
/// field holds focus for the whole presentation, so the survey's answer field could never take it;
/// the survey keeps appearing in the full Launcher.
struct CompactLauncherSuggestions: View {
    let model: CompactLauncherModel
    let applications: [LauncherApplication]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.launcherSuggestionsSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: CompactLauncherLayout.spacing) {
                ForEach(applications) { application in
                    CompactLauncherTile(application: application, launcher: model.launcher,
                                        selected: model.selectedID == .suggested(application.id), isSuggestion: true)
                        .id(LauncherBrowseID.suggested(application.id))
                }
            }
            Divider()
                .padding(.top, 8)
                .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        .onAppear { model.launcher.recordSuggestionImpression() }
        .onChange(of: applications.map(\.id)) { _, _ in model.launcher.recordSuggestionImpression() }
    }
}
