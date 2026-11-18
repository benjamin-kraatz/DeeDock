import AppKit
import SwiftUI

private final class WindowPeekHeroControlWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The enlarged stage stays click-through. Only the small reveal control accepts mouse events.
@MainActor
final class WindowPeekHeroPrivacyPanel {
    private let panel: NSPanel

    init(hero: CGRect, level: NSWindow.Level, sensitive: WindowPeekSensitiveExhibit) {
        let size = CGSize(width: min(200, hero.width), height: min(36, hero.height))
        let frame = CGRect(x: hero.midX - size.width / 2,
                           y: hero.minY + max(0, min(14, hero.height - size.height)),
                           width: size.width, height: size.height)
        panel = WindowPeekHeroControlWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = WindowPeekHeroToolbarHostingView(rootView: WindowPeekHeroPrivacyButton(sensitive: sensitive))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    func owns(_ window: NSWindow?) -> Bool { window === panel }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

private struct WindowPeekHeroPrivacyButton: View {
    let sensitive: WindowPeekSensitiveExhibit

    var body: some View {
        if let control = sensitive.control() {
            let label: LocalizedStringResource = control.isRevealed ? .windowPreviewHide : .windowPreviewReveal
            let hint: LocalizedStringResource = control.isRevealed ? .windowPreviewHideHelp : .windowPreviewSensitiveMessage
            ViewThatFits {
                Button(label, action: control.action).fixedSize()
                Button(action: control.action) {
                    Image(systemName: control.isRevealed ? "eye.slash" : "eye")
                }
                .accessibilityLabel(Text(label))
            }
            .buttonStyle(.borderedProminent)
            .tint(.secondary)
            .help(Text(hint))
            .accessibilityHint(Text(hint))
        }
    }
}
