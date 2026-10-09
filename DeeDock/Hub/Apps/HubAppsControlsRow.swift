import SwiftUI

/// The slim row above the app grid (mockup `.sect` with chips): a title, the Robi chip or Ask Robi,
/// "Recently used" / "A–Z" sort chips, and the options menu that carries the remaining launcher
/// controls (result type, filters, location, grouping, layout, Choose Files, Capture & image
/// search, refresh, clear history, Settings).
///
/// The header search field belongs to the Hub shell; this row replaces the rest of the old
/// launcher search bar.
struct HubAppsControlsRow: View {
    let launcher: LauncherState
    /// Asks the tab to confirm clearing launch history.
    let requestClearHistory: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if launcher.robiActive, !launcher.robiBusy {
                LauncherRobiScopeChip { launcher.cancelRobi() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            title
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.numericText())
            if launcher.library.isLoading {
                ProgressView().controlSize(.mini)
            }
            if launcher.library.skippedDirectories > 0 {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(Text(.launcherDiscoveryIncomplete))
                    .accessibilityLabel(Text(.launcherDiscoveryIncomplete))
            }
            Spacer(minLength: 8)
            if !launcher.usesFileActions, !launcher.robiActive || launcher.robiBusy {
                LauncherRobiButton(state: launcher).fixedSize()
            }
            if showsSortChips {
                HubAppsSortChips(launcher: launcher)
            }
            LauncherSearchBarOverflowMenu(state: launcher, requestClearHistory: requestClearHistory)
        }
        .padding(EdgeInsets(top: 6, leading: 4, bottom: 12, trailing: 4))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: launcher.robiActive)
    }

    /// Sorting applies to apps, so the chips hide for file actions and non-app result types.
    private var showsSortChips: Bool {
        !launcher.usesFileActions && (launcher.search.kind == .all || launcher.search.kind == .application)
    }

    private var title: Text {
        if launcher.usesFileActions {
            return Text(.launcherFileActionCount(launcher.fileActions.actions.count))
        }
        if launcher.usesMixedResults {
            return Text(.unifiedResultCount(launcher.search.results.count))
        }
        if launcher.query.isEmpty, launcher.filter == .all, !launcher.robiActive {
            return Text(.hubAppsAllApps)
        }
        return Text(.launcherResultCount(launcher.results.count))
    }
}

/// "Recently used" and "A–Z" (mockup `.chips`). Other orders stay in the options menu; while one
/// of those is active neither chip is highlighted.
private struct HubAppsSortChips: View {
    let launcher: LauncherState

    var body: some View {
        HStack(spacing: 6) {
            chip(.recent, title: .hubAppsSortRecent)
            chip(.name, title: .hubAppsSortName)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.hubAppsSortLabel))
    }

    private func chip(_ sort: LauncherSort, title: LocalizedStringResource) -> some View {
        HubAppsChip(title: title, isOn: launcher.sort == sort) { launcher.sort = sort }
    }
}

/// A small text toggle chip: secondary on the chip wash, primary on the brighter wash when on.
private struct HubAppsChip: View {
    let title: LocalizedStringResource
    let isOn: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(isOn || hovered ? HubAppsStyle.chipHighlight(colorScheme) : HubAppsStyle.chip(colorScheme),
                            in: .rect(cornerRadius: 8, style: .continuous))
                .contentShape(.rect(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.hubPress(scale: 0.95))
        .onHover { hovered = $0 }
        .animation(.snappy(duration: 0.15), value: hovered)
        .animation(.snappy(duration: 0.15), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
