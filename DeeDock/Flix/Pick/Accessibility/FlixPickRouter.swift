import AppKit

/// What one Flix Pick action did to the picker.
struct FlixPickActionResult: Equatable {
    var route: AnalyticsFlixPickRoute
    /// The picker shows the file (selected) or the folder now, or at least the jump went through.
    var selected: Bool
    /// The default button was pressed.
    var confirmed = false
    var failure: AnalyticsFlixPickFailure?
}

/// Puts a file or folder into another app's picker, the cheapest way that works, and presses the
/// default button when asked.
///
/// 1. **Already there**: the picker shows the folder, or has the file selected.
/// 2. **Listed row** (Open pickers with a list view): the file is among the rows of the folder the
///    picker shows; its row is selected through Accessibility (about 70 ms, nothing on screen).
/// 3. **Go to Folder**: ⇧⌘G, the full path into `PathTextField`, Return (0.1–0.4 s; the Go to
///    Folder sheet flashes). For a file path macOS selects the file. Before each keystroke the
///    person must have let go of every modifier, the picker's app must be frontmost, and the
///    picker must have focus; any of those failing stops here. Never while Secure Event Input is
///    on. If the sheet stays open (the path is gone), Escape closes it, but only while the
///    focused element is still that field, so the picker itself is never cancelled.
/// 4. **Confirm** (⌥-click, double-click): only when the picker's selection (Open) or folder
///    (Save) was read back and matches, `OKButton` is pressed. A Save picker keeps the typed name
///    when it changes folder. Without a readable list view (column or icon view) the jump still
///    happens but nothing is pressed.
///
/// Every step checks the picker by its serial and gives up when it is gone; the caller cancels the
/// task when the picker closes. Main actor; the Accessibility calls run on `FlixAXThread`.
@MainActor
enum FlixPickRouter {
    /// - Parameters:
    ///   - folderName: How the folder popup names `path` (Save pickers), for checking an empty folder.
    ///   - willConfirm: Runs right before `OKButton` is pressed, so the caller knows a close that
    ///     follows was Flix Pick's own confirm even when it is reported before this returns.
    static func perform(path: String, folderName: String, picker: FlixPickPicker, confirm: Bool,
                        observer: FlixPickObserver, willConfirm: () -> Void = {}) async -> FlixPickActionResult {
        let serial = picker.serial
        let isSave = picker.kind == .save
        var route: AnalyticsFlixPickRoute?
        if await shows(path, folderName: folderName, isSave: isSave, serial: serial, observer: observer) {
            route = .alreadyThere
        } else if !isSave, picker.hasListView {
            switch await observer.run({ $0.selectListed(path, serial: serial) }) {
            case .selected:
                if await shows(path, folderName: folderName, isSave: false, serial: serial, observer: observer) {
                    route = .listedRow
                }
            case .gone:
                return FlixPickActionResult(route: .listedRow, selected: false, failure: .pickerClosed)
            case .notListed, .unavailable:
                break
            }
        }
        if route == nil {
            if let failure = await goToFolder(path, picker: picker, observer: observer) {
                return FlixPickActionResult(route: .goToFolder, selected: false, failure: failure)
            }
            route = .goToFolder
        }
        guard !Task.isCancelled else { return FlixPickActionResult(route: route!, selected: false, failure: .pickerClosed) }
        guard confirm else { return FlixPickActionResult(route: route!, selected: true) }
        // Confirm only what was read back: a jump the picker did not follow must not open anything.
        let verified = await poll(for: .milliseconds(800)) {
            await shows(path, folderName: folderName, isSave: isSave, serial: serial, observer: observer)
        }
        guard verified, picker.canConfirm else {
            return FlixPickActionResult(route: route!, selected: true, failure: .notVerified)
        }
        willConfirm()
        let pressed = await observer.run { $0.pressDefaultButton(serial: serial) }
        return FlixPickActionResult(route: route!, selected: true, confirmed: pressed,
                                    failure: pressed ? nil : .notVerified)
    }

    /// Whether the picker has `path` selected (Open) or shows it as its folder (Save).
    private static func shows(_ path: String, folderName: String, isSave: Bool, serial: Int,
                              observer: FlixPickObserver) async -> Bool {
        if isSave { return await observer.run { $0.shows(folder: path, displayName: folderName, serial: serial) } }
        guard case .selected(let url?) = await observer.run({ $0.selection(serial: serial) }) else { return false }
        return FlixPickAX.same(url, path)
    }

    /// Go to Folder: ⇧⌘G, the path, Return. Nil when the sheet opened, took the path, and closed.
    private static func goToFolder(_ path: String, picker: FlixPickPicker,
                                   observer: FlixPickObserver) async -> AnalyticsFlixPickFailure? {
        let serial = picker.serial
        guard FlixPickKeys.canType else { return .secureInput }
        guard await FlixPickKeys.waitForModifiersReleased() else { return Task.isCancelled ? .pickerClosed : .modifiersHeld }
        guard await stillInFront(picker, observer: observer) else { return .notFrontmost }
        FlixPickKeys.press(FlixPickKeys.goToFolderKey, flags: [.maskShift, .maskCommand])
        let opened = await poll(for: .milliseconds(1_200)) {
            await observer.run { $0.pathFieldHasFocus(serial: serial) }
        }
        guard opened else { return Task.isCancelled ? .pickerClosed : .noPathField }
        guard await observer.run({ $0.enterPath(path, serial: serial) }) else {
            await escape(picker, observer: observer)
            return .noPathField
        }
        // The person may have pressed a modifier meanwhile, or moved to another app.
        guard await FlixPickKeys.waitForModifiersReleased(timeout: .milliseconds(600)),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == picker.processIdentifier,
              await observer.run({ $0.pathFieldHasFocus(serial: serial) }) else {
            await escape(picker, observer: observer)
            return .notFrontmost
        }
        FlixPickKeys.press(FlixPickKeys.returnKey)
        let closed = await poll(for: .milliseconds(1_500)) {
            !(await observer.run { $0.pathFieldHasFocus(serial: serial) })
        }
        guard closed else {
            await escape(picker, observer: observer)
            return .notVerified
        }
        return nil
    }

    /// Closes the Go to Folder sheet with Escape, only while its field still has focus in the
    /// frontmost picker, so the picker itself is never cancelled.
    private static func escape(_ picker: FlixPickPicker, observer: FlixPickObserver) async {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == picker.processIdentifier,
              !FlixPickKeys.modifiersHeld,
              await observer.run({ $0.pathFieldHasFocus(serial: picker.serial) }) else { return }
        FlixPickKeys.press(FlixPickKeys.escapeKey)
    }

    private static func stillInFront(_ picker: FlixPickPicker, observer: FlixPickObserver) async -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == picker.processIdentifier else { return false }
        let serial = picker.serial
        return await observer.run { $0.hasFocus(serial: serial) }
    }

    /// Checks `condition` every 30 ms until it holds or `timeout` passes. Short polling of the
    /// picker's own state, only while an action runs.
    private static func poll(for timeout: Duration, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !Task.isCancelled {
            if await condition() { return true }
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }
}
