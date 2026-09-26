import AppKit
import SwiftUI

/// What the hero toolbar can do with the staged picture.
struct WindowPeekHeroToolbarActions {
    let markup: () -> Void
    /// Copies the staged picture; returns whether it reached the pasteboard.
    let copy: () -> Bool
    let save: () -> Void
}

/// Buttons must act on the first click; the panel never becomes key, so there is no second one.
private final class WindowPeekHeroToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The small glass strip that appears on the enlarged preview once the pointer rests on it.
///
/// The stage panel stays click-through so the cards keep working, so these controls live in their
/// own tiny mouse-accepting panel over the hero's top-right corner. Peek's outside-click monitor
/// treats it as Peek's own window, and the enlarge controller ignores its clicks.
@MainActor
final class WindowPeekHeroToolbarPanel {
    static let size = CGSize(width: 214, height: 40)
    /// Inset from the hero's top and right edges.
    static let inset: CGFloat = 12
    private let panel: NSPanel

    init(level: NSWindow.Level, actions: WindowPeekHeroToolbarActions) {
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let hosting = WindowPeekHeroToolbarHostingView(rootView: WindowPeekHeroToolbarView(actions: actions))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    /// The toolbar's frame for a hero at `hero`, in screen coordinates.
    static func frame(forHero hero: CGRect) -> CGRect {
        CGRect(x: hero.maxX - inset - size.width, y: hero.maxY - inset - size.height,
               width: size.width, height: size.height)
    }

    func show(forHero hero: CGRect) {
        panel.setFrame(Self.frame(forHero: hero), display: false)
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    func owns(_ window: NSWindow?) -> Bool { window === panel }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

/// Mark up, copy, save. Copy confirms in place by swapping its icon for a check.
struct WindowPeekHeroToolbarView: View {
    let actions: WindowPeekHeroToolbarActions
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 2) {
            Button(action: actions.markup) {
                Label(.markupOpenShort, systemImage: "pencil.tip.crop.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .help(Text(.markupOpen))
            Button {
                guard actions.copy() else { return }
                copied = true
                resetTask?.cancel()
                resetTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1_400))
                    guard !Task.isCancelled else { return }
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(Text(.markupCopyHelp))
            .accessibilityLabel(Text(.markupCopy))
            Button(action: actions.save) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(Text(.markupSave))
            .accessibilityLabel(Text(.markupSave))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .modifier(PortalChrome(opaque: reduceTransparency))
        .frame(width: WindowPeekHeroToolbarPanel.size.width, height: WindowPeekHeroToolbarPanel.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.markupHeroToolbarAccessibility))
    }
}

#if DEBUG
#Preview("Hero toolbar") {
    WindowPeekHeroToolbarView(actions: .init(markup: {}, copy: { true }, save: {}))
        .padding(30)
        .background(.gray)
}
#endif
