import AppKit
import SwiftUI

/// The More pill's menu: a native `NSMenu` popped up under the pill.
///
/// Not a SwiftUI `Menu`: on macOS its label is drawn as a pop-up button and ignores
/// `RobiPillStyle`, so the More pill would not match its neighbours. An `NSMenu` popped up from
/// the pill's own view tracks normally in Robi's non-activating panel and leaves the app in front.
enum RobiMoreMenu {
    /// One line of the menu.
    enum Entry {
        case item(title: String, symbol: String, isEnabled: Bool, action: () -> Void)
        case separator
        case header(String)
    }

    /// Shows `entries` under `view`, aligned with its leading edge like a pull-down button, and
    /// returns when the menu closes. The chosen item's action runs before that.
    ///
    /// - Parameter dark: Draws the menu dark to match pills on a dark title bar.
    static func show(_ entries: [Entry], under view: NSView, dark: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        for entry in entries {
            switch entry {
            case let .item(title, symbol, isEnabled, action):
                menu.addItem(RobiMenuItem(title: title, symbol: symbol, isEnabled: isEnabled, action: action))
            case .separator:
                menu.addItem(.separator())
            case let .header(title):
                menu.addItem(.sectionHeader(title: title))
            }
        }
        // The point is the menu's top-left corner, in the view's own coordinates.
        let below = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: below), in: view)
    }
}

/// A menu item that runs a closure. The menu keeps the item, and the item is its own target.
private final class RobiMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String, isEnabled: Bool, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(RobiMenuItem.fire), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.isEnabled = isEnabled
    }

    required init(coder: NSCoder) {
        fatalError("RobiMenuItem is created in code only")
    }

    @objc private func fire() { handler() }
}

/// Holds the AppKit view behind a pill, so a SwiftUI button can pop up a menu from it.
final class RobiMenuAnchor {
    weak var view: NSView?
}

/// A transparent view laid behind a pill that hands itself to a `RobiMenuAnchor`.
struct RobiMenuAnchorView: NSViewRepresentable {
    let anchor: RobiMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = RobiClickThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// Never the target of a click. AppKit hit-tests real views before SwiftUI content, so without
/// this the anchor behind the pill would take the pill's clicks.
private final class RobiClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
