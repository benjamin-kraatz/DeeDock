import AppKit

/// One compact Launcher presentation in a dock popover above the Launcher tile.
///
/// The shared ``DockPopoverPanelController`` owns the window, outside-click dismissal, and motion.
/// This controller owns the Launcher lifecycle on the dock's ``LauncherState``: it begins and ends
/// the presentation, closes after an app opens, and returns focus to the previous app on Escape.
/// A presentation is single-use; the dock builds a new controller for every opening.
@MainActor
final class CompactLauncherController {
    private let launcher: LauncherState
    private let model: CompactLauncherModel
    private let popover: DockPopoverPanelController<CompactLauncherView>
    private var previousApplication: NSRunningApplication?
    /// Runs once after the presentation ends, whichever path closed it.
    var didClose: (() -> Void)?

    init(launcher: LauncherState, anchor: DockPopoverAnchor, pins: [ApplicationReference],
         previousApplication: NSRunningApplication?) {
        let model = CompactLauncherModel(launcher: launcher)
        self.launcher = launcher
        self.model = model
        self.previousApplication = previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil : previousApplication
        launcher.begin(pins: pins, foregroundID: self.previousApplication?.bundleIdentifier, style: .compact)
        // `clickFocus` routes key-downs through `keyHandler` before the search field's editor sees them.
        popover = DockPopoverPanelController(anchor: anchor, keyboard: true, clickFocus: true, activates: true,
                                             windowShadow: false, ideal: CompactLauncherLayout.idealSize) { chrome in
            model.chrome = chrome
        } content: {
            CompactLauncherView(model: model)
        }
        popover.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        popover.resignedKey = { [weak self] in self?.focusMoved() }
        popover.canDismissForOutsideClick = { [weak launcher] in launcher?.fileActions.isChoosing != true }
        popover.closed = { [weak self] restore in self?.finish(restoreFocus: restore) }
        launcher.close = { [weak self] in self?.close(restoreFocus: true) }
        launcher.didOpen = { [weak self] in self?.close(restoreFocus: false) }
    }

    func show() {
        launcher.isPresented = true
        popover.show()
    }

    /// Follows the Launcher tile when the dock moves, resizes, or scrolls.
    func update(_ anchor: DockPopoverAnchor) { popover.update(anchor) }

    /// - Parameter restoreFocus: Reactivates the app that was frontmost before the Launcher opened.
    func close(restoreFocus: Bool) { popover.close(returnFocus: restoreFocus) }

    /// Clicking another app or Command-Tab moves key focus away; the Launcher steps aside like a menu.
    private func focusMoved() {
        guard launcher.isPresented, NSApp.keyWindow?.level != .popUpMenu else { return }
        close(restoreFocus: false)
    }

    private func finish(restoreFocus: Bool) {
        guard launcher.isPresented else { return }
        launcher.isPresented = false
        launcher.end()
        if restoreFocus, NSApp.isActive, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        let callback = didClose
        didClose = nil
        callback?()
    }

    /// Keys reach this before the search field. Only navigation, Return, and Escape are claimed;
    /// everything else, including Left and Right before navigation starts, edits the query.
    private func handleKey(_ event: NSEvent) -> Bool {
        if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false // Input-method candidates own arrows, Return, and Escape until composition ends.
        }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        let columns = CompactLauncherLayout.columns
        switch event.keyCode {
        case 53:
            if model.navigating { model.clearSelection() }
            else if !model.query.isEmpty { model.query = "" }
            else { close(restoreFocus: true) }
        case 36, 76: model.openSelection()
        case 125: model.move(by: model.navigating ? columns : 0)
        case 126 where model.navigating: model.move(by: -columns)
        case 123 where model.navigating: model.move(by: -1)
        case 124 where model.navigating: model.move(by: 1)
        default: return false
        }
        return true
    }
}
