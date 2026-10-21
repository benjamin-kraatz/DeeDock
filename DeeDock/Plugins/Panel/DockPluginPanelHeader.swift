import SwiftUI

/// The bar DOKK draws above every plugin's content: the app icon, the plugin's name, the app's
/// name when it differs, and a More button with the tile's menu.
///
/// Exactly ``DockPluginPanelGeometry/headerHeight`` tall, so the plugin's requested content size
/// is what it gets below.
struct DockPluginPanelHeader<More: View>: View {
    let icon: NSImage
    let title: String
    let appName: String?
    @ViewBuilder var more: More

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            if let appName {
                Text(verbatim: appName)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            more
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: DockPluginPanelGeometry.headerHeight)
        .overlay(alignment: .bottom) { Divider().opacity(0.8) }
    }
}

/// The header's More button. It opens the plugin tile's menu right under itself.
///
/// AppKit-backed so the menu is the same `NSMenu` the tile shows, and so the panel can tell its
/// clicks apart from clicks outside.
struct DockPluginMoreButton: View {
    let plugin: DockPlugin
    let state: DockPluginPanelState
    @State private var hovered = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DockPluginMoreButtonBridge(plugin: plugin, state: state, openSettingsWindow: { openWindow.openDockSettings() })
            .frame(width: 28, height: 28)
            .background(hovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 8, style: .continuous))
            .onHover { hovered = $0 }
            .help(Text(.pluginPanelMore))
    }
}

private struct DockPluginMoreButtonBridge: NSViewRepresentable {
    let plugin: DockPlugin
    let state: DockPluginPanelState
    let openSettingsWindow: () -> Void

    func makeNSView(context: Context) -> MoreButton { MoreButton() }
    func updateNSView(_ view: MoreButton, context: Context) {
        view.plugin = plugin
        view.panelState = state
        view.openSettingsWindow = openSettingsWindow
    }
    static func dismantleNSView(_ view: MoreButton, coordinator: ()) { view.stop() }

    final class MoreButton: NSButton {
        weak var plugin: DockPlugin?
        weak var panelState: DockPluginPanelState?
        var openSettingsWindow: (() -> Void)?
        private let menuTarget = DockPluginMenuTarget()

        init() {
            super.init(frame: .zero)
            isBordered = false
            imagePosition = .imageOnly
            image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: String(localized: .pluginPanelMore))
            contentTintColor = .secondaryLabelColor
            setButtonType(.momentaryChange)
            target = self
            action = #selector(showMenu)
        }

        required init?(coder: NSCoder) { nil }

        @objc private func showMenu() {
            guard let plugin, let panelState, var actions = panelState.menuActions else { return }
            let routeSettings = actions.openSettings
            let openSettingsWindow = openSettingsWindow
            actions.openSettings = {
                routeSettings()
                openSettingsWindow?()
            }
            menuTarget.reset()
            menuTarget.actions = actions
            let menu = DockPluginMenu.make(for: plugin, panelOpen: true, target: menuTarget)
            panelState.menuTracking = true
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
            panelState.menuTracking = false
        }

        func stop() {
            menuTarget.reset()
            plugin = nil
            panelState = nil
            openSettingsWindow = nil
        }
    }
}
