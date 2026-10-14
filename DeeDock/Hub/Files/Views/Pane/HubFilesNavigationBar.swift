import SwiftUI

/// The 42 pt bar above a pane: back, forward, and breadcrumbs from the nearest sidebar location.
struct HubFilesNavigationBar: View {
    let model: HubFilesModel
    let pane: HubFilesPane
    let index: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 2) {
            HubFilesNavigationButton(symbol: "chevron.left", label: .hubFilesBack, enabled: pane.canGoBack) {
                model.activatePane(index)
                pane.goBack()
            }
            HubFilesNavigationButton(symbol: "chevron.right", label: .hubFilesForward, enabled: pane.canGoForward) {
                model.activatePane(index)
                pane.goForward()
            }
            HubFilesBreadcrumbs(model: model, pane: pane, index: index, isActive: isActive)
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: HubFilesMetrics.navigationBarHeight)
    }
}

/// A 26 pt back or forward button.
private struct HubFilesNavigationButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let enabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(hovered && enabled ? HubFilesTheme(scheme).chip : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.88))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { hovered = $0 }
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Clickable path segments from the nearest sidebar location to the current folder.
private struct HubFilesBreadcrumbs: View {
    let model: HubFilesModel
    let pane: HubFilesPane
    let index: Int
    let isActive: Bool

    var body: some View {
        let crumbs: [HubFilesLocation] = pane.location == .recents
            ? [.recents] : pane.pathChain.map(HubFilesLocation.folder)
        HStack(spacing: 3) {
            HubFilesFolderIcon(url: pane.folderURL ?? model.home, size: 18)
            ForEach(Array(crumbs.enumerated()), id: \.offset) { offset, location in
                let isLast = offset == crumbs.count - 1
                if offset > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                HubFilesCrumb(model: model, pane: pane, index: index, location: location,
                              isLast: isLast, isActive: isActive)
                    .layoutPriority(isLast ? 1 : 0)
            }
        }
        .lineLimit(1)
    }
}

/// One breadcrumb segment. A click shows its folder; during a drag it is a drop target, and
/// resting on an ancestor segment opens it (`HubFilesInteractions.crumb`).
private struct HubFilesCrumb: View {
    let model: HubFilesModel
    let pane: HubFilesPane
    let index: Int
    let location: HubFilesLocation
    let isLast: Bool
    let isActive: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    private var title: String { model.displayName(for: location) }
    private var isDropTarget: Bool {
        location.folderURL.map { model.dropHighlight == .crumb(pane: pane.id, folder: $0) } ?? false
    }

    var body: some View {
        let theme = HubFilesTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 6)
        Text(verbatim: title)
            .font(.system(size: 13.5, weight: isLast ? (isActive ? .semibold : .medium) : .regular))
            .foregroundStyle(isLast || hovered || isDropTarget ? .primary : .secondary)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 24)
            .background(isDropTarget ? theme.accentSelection : hovered ? theme.chip : .clear, in: shape)
            .overlay {
                if isDropTarget { shape.strokeBorder(theme.accentLine, lineWidth: 1) }
            }
            // A small lift tells the target apart from plain hover; scaling leaves the bar's layout alone.
            .scaleEffect(isDropTarget ? 1.06 : 1)
            .overlay {
                HubFilesInteractionRegion(
                    interaction: HubFilesInteractions.crumb(location, isCurrent: isLast, pane: pane, paneIndex: index,
                                                            model: model) { hovered = $0 },
                    model: model)
            }
            .animation(HubFilesMotion.animation(.spring(response: 0.25, dampingFraction: 0.7)), value: isDropTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.activatePane(index)
                pane.navigate(to: location)
            }
    }
}
