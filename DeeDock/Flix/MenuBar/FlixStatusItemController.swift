import AppKit

/// The optional Flix Files menu bar item, off by default. A click opens the panel under it.
///
/// It shows a count while items arrived since you last looked, matching the tile's badge; the
/// coordinator calls ``update()`` whenever the history changes. The status item is removed from
/// the menu bar by ``stop()``.
@MainActor
final class FlixStatusItemController: NSObject {
    private let item: NSStatusItem
    private let tile: FlixTileState
    private let toggle: (CGRect) -> Void

    /// - Parameter toggle: Receives the item's frame in screen coordinates.
    init(tile: FlixTileState, toggle: @escaping (CGRect) -> Void) {
        self.tile = tile
        self.toggle = toggle
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: String(localized: .flixName))
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.toolTip = String(localized: .flixName)
            button.setAccessibilityLabel(String(localized: .flixName))
        }
        update()
    }

    @objc private func clicked() {
        guard let button = item.button, let window = button.window else { return }
        toggle(window.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    /// Redraws the count from the tile state.
    func update() {
        let count = tile.unseenCount
        item.button?.title = count > 0 ? " \(min(count, 99).formatted())" : ""
        item.button?.setAccessibilityValue(count > 0 ? String(localized: .flixUnseenCount(count)) : nil)
    }

    func stop() {
        NSStatusBar.system.removeStatusItem(item)
    }
}
