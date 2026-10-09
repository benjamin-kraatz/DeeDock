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
                HubFilesCrumb(title: model.displayName(for: location), isLast: isLast, isActive: isActive) {
                    model.activatePane(index)
                    pane.navigate(to: location)
                }
                .layoutPriority(isLast ? 1 : 0)
            }
        }
        .lineLimit(1)
    }
}

/// One breadcrumb segment.
private struct HubFilesCrumb: View {
    let title: String
    let isLast: Bool
    let isActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13.5, weight: isLast ? (isActive ? .semibold : .medium) : .regular))
                .foregroundStyle(isLast || hovered ? .primary : .secondary)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(minWidth: 24)
                .background(hovered ? HubFilesTheme(scheme).chip : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(Text(verbatim: title))
    }
}
