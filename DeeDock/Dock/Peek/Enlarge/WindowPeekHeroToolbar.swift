import AppKit
import SwiftUI

/// Where the hero toolbar's Save puts the picture.
///
/// The Shelf when its tile is on, since that is where the picture can be picked up again; otherwise
/// the Downloads folder, the place people look for a file they did not name.
enum WindowPeekHeroSaveTarget {
    case shelf, downloads

    var title: LocalizedStringResource {
        switch self {
        case .shelf: .markupHeroSaveToShelf
        case .downloads: .markupHeroSaveToDownloads
        }
    }

    var symbol: String {
        switch self {
        case .shelf: "tray.and.arrow.down"
        case .downloads: "arrow.down.circle"
        }
    }
}

/// What Save did, so the toolbar knows whether to confirm in place.
enum WindowPeekHeroSaveOutcome {
    /// The picture is flying into its dock tile; the toolbar is already going away.
    case flew
    /// Saved, with no flight to show it; the button confirms with a check.
    case saved
    case failed
}

/// A picture the coordinator saved for the hero toolbar.
struct WindowPeekSavedPicture {
    /// The Shelf or Downloads tile on the Peek's dock, in AppKit screen coordinates; `nil` without one.
    let tile: CGRect?
    /// Called once the picture reaches the tile, or at once when there is no flight.
    let arrived: () -> Void
}

/// What the hero toolbar can do with the staged picture.
struct WindowPeekHeroToolbarActions {
    let markup: () -> Void
    /// Copies the staged picture; returns whether it reached the pasteboard.
    let copy: () -> Bool
    let saveTarget: WindowPeekHeroSaveTarget
    /// Saves the staged picture to `saveTarget` without a panel.
    let save: () -> WindowPeekHeroSaveOutcome
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

/// Mark up, copy, save. Copy, and Save when it has no flight to show, confirm in place by swapping
/// the icon for a check; a failed save shows a warning instead.
struct WindowPeekHeroToolbarView: View {
    let actions: WindowPeekHeroToolbarActions
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @State private var saveOutcome: WindowPeekHeroSaveOutcome?
    @State private var saveResetTask: Task<Void, Never>?
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
            Button(action: save) {
                Image(systemName: saveSymbol)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(saveOutcome == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help(Text(actions.saveTarget.title))
            .accessibilityLabel(Text(actions.saveTarget.title))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .modifier(PortalChrome(opaque: reduceTransparency))
        .frame(width: WindowPeekHeroToolbarPanel.size.width, height: WindowPeekHeroToolbarPanel.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.markupHeroToolbarAccessibility))
    }

    private var saveSymbol: String {
        switch saveOutcome {
        case .saved: "checkmark"
        case .failed: "exclamationmark.triangle"
        case .flew, nil: actions.saveTarget.symbol
        }
    }

    private func save() {
        let outcome = actions.save()
        // A flight is its own confirmation, and the toolbar fades out as it starts.
        guard outcome != .flew else { return }
        saveOutcome = outcome
        saveResetTask?.cancel()
        saveResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(outcome == .failed ? 2_200 : 1_400))
            guard !Task.isCancelled else { return }
            saveOutcome = nil
        }
    }
}

#if DEBUG
#Preview("Hero toolbar, Shelf") {
    WindowPeekHeroToolbarView(actions: .init(markup: {}, copy: { true }, saveTarget: .shelf, save: { .saved }))
        .padding(30)
        .background(.gray)
}
#Preview("Hero toolbar, Downloads, failing save, German") {
    WindowPeekHeroToolbarView(actions: .init(markup: {}, copy: { false }, saveTarget: .downloads, save: { .failed }))
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
        .padding(30)
        .background(.gray)
}
#endif
