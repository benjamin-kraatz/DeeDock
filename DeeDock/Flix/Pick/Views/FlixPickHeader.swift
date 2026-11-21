import AppKit
import SwiftUI

/// The panel's header: the Flix logo, "Flix Pick", whom it is for, and the ⋯ menu. In the closed
/// rail only the logo shows.
struct FlixPickHeader: View {
    let state: FlixPickState

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            FlixPickLogo(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(.flixPickName)
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
            .lineLimit(1)
            .flixPickReveal(state.isOpen)
            Spacer(minLength: 4)
            FlixPickMoreButton(appName: state.appName,
                               disableForApp: { state.disableForApp?() },
                               openSettings: {
                                   state.prepareSettings?()
                                   openWindow.openDockSettings()
                               },
                               tracking: { state.menuTracking?($0) })
                .flixPickReveal(state.isOpen)
                .allowsHitTesting(state.isOpen)
                .accessibilityHidden(!state.isOpen)
        }
        .padding(.leading, 19)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .frame(height: FlixPickPlacement.headerHeight)
    }

    private var subtitle: String {
        switch state.kind {
        case .open:
            guard let button = state.buttonTitle, !button.isEmpty else { return String(localized: .flixPickSubtitleOpenPlain(state.appName)) }
            return String(localized: .flixPickSubtitleOpen(state.appName, button))
        case .save:
            return String(localized: .flixPickSubtitleSave(state.appName))
        }
    }
}

/// Flix Files' mark in small: the blue-to-indigo gradient square with a white document.
struct FlixPickLogo: View {
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(stops: [.init(color: Color(red: 0.353, green: 0.784, blue: 0.98), location: 0),
                                         .init(color: Color(red: 0.039, green: 0.518, blue: 1), location: 0.55),
                                         .init(color: Color(red: 0.369, green: 0.361, blue: 0.902), location: 1)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

/// The ⋯ button: **Not in <App>** and **Flix Pick Settings…**, as a native menu.
struct FlixPickMoreButton: View {
    let appName: String
    let disableForApp: () -> Void
    let openSettings: () -> Void
    let tracking: (Bool) -> Void

    var body: some View {
        Button(action: showMenu) {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(FlixPickIconButtonStyle())
        .help(Text(.flixPickMore))
        .accessibilityLabel(Text(.flixPickMore))
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(FlixPickMenuItem(title: String(localized: .flixPickNotInApp(appName)), symbol: "eye.slash",
                                      handler: disableForApp))
        menu.addItem(.separator())
        menu.addItem(FlixPickMenuItem(title: String(localized: .flixPickSettings), symbol: "gearshape",
                                      handler: openSettings))
        tracking(true)
        // Screen coordinates: the panel never becomes key, so the menu opens at the pointer.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        tracking(false)
    }
}

/// Quiet until hovered, dimmed while pressed.
private struct FlixPickIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlixHover { hovered in
            configuration.label
                .foregroundStyle(hovered ? Color.primary : FlixStyle.faint)
                .background(hovered ? FlixStyle.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

/// A menu item that runs a closure.
private final class FlixPickMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
