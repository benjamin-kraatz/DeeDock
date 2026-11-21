import AppKit

/// What one Flix Pick action did to the picker.
struct FlixPickActionResult: Equatable {
    var route: AnalyticsFlixPickRoute
    /// The picker shows the file (selected) or the folder now, or at least the jump went through.
    var selected: Bool
    /// The default button was pressed, and the press went through.
    var confirmed = false
    var failure: AnalyticsFlixPickFailure?
    /// When the press went through.
    var confirmedAt: Date?
    /// The picker was gone within ``FlixPickRouter/closeWindow`` of the press. Only then is the
    /// press Flix Pick's pick: a picker still open (a "Replace?" prompt, a refused name) was not
    /// closed by it.
    var closedByPress = false
}

/// Puts a file or folder into another app's picker, the cheapest way that works, and presses the
/// default button when asked.
///
/// 1. **Already there**: exactly that file is selected (Open), or the picker's listed rows are
///    inside that folder (Save). A folder's name is never proof of its place.
/// 2. **Listed row** (Open pickers with a list view): the file is among the rows of the folder the
///    picker shows; the selection is replaced by its row through Accessibility (about 70 ms,
///    nothing on screen).
/// 3. **Go to Folder**: ⇧⌘G, the full path into `PathTextField`, then the sheet is sent on: the
///    field's `AXConfirm`, else the sheet's default button, else Return. Keys are posted by the
///    Accessibility thread right after checking, in the same block, that the picker's app has
///    keyboard focus, the picker is focused, no modifier is held, and Secure Event Input is off;
///    Return also needs the focused element to still be the field holding the path. When a check
///    fails, the sheet stays open with the path typed; when it stays open after being sent on
///    (the path is gone), it is dismissed with the field's `AXCancel` or the sheet's cancel
///    button, never with Escape.
/// 4. **Confirm** (⌥-click, double-click): once the picker shows exactly that file or that
///    folder's rows, one Accessibility block checks everything again (the attachment the action
///    started under, the picker in front and focused, the exact selection or folder, the button
///    enabled) and presses `OKButton`. A Save picker keeps the typed name. An empty folder, or a
///    picker without a readable list view (column or icon view), is moved to but never confirmed.
///
/// Every step names the picker by its serial and gives up when it is gone; the caller cancels the
/// task when the picker closes. Main actor; the Accessibility calls run on `FlixAXThread`.
@MainActor
enum FlixPickRouter {
    /// How long after a press that went through the picker must be gone for the press to count
    /// as what closed it.
    static let closeWindow: Duration = .milliseconds(600)

    static func perform(path: String, picker: FlixPickPicker, confirm: Bool,
                        observer: FlixPickObserver) async -> FlixPickActionResult {
        let serial = picker.serial
        let isSave = picker.kind == .save
        // Any app switch after this point bumps the generation, and the final checks refuse.
        let generation = observer.generation
        var route: AnalyticsFlixPickRoute?
        if await shows(path, isSave: isSave, serial: serial, observer: observer) {
            route = .alreadyThere
        } else if !isSave, picker.hasListView {
            switch await observer.run({ $0.selectListed(path, serial: serial) }) {
            case .selected:
                if await shows(path, isSave: false, serial: serial, observer: observer) { route = .listedRow }
            case .gone:
                return FlixPickActionResult(route: .listedRow, selected: false, failure: .pickerClosed)
            case .notListed, .unavailable:
                break
            }
        }
        if route == nil {
            if let failure = await goToFolder(path, picker: picker, generation: generation, observer: observer) {
                return FlixPickActionResult(route: .goToFolder, selected: false, failure: failure)
            }
            route = .goToFolder
        }
        guard let route, !Task.isCancelled else {
            return FlixPickActionResult(route: route ?? .goToFolder, selected: false, failure: .pickerClosed)
        }
        guard confirm else { return FlixPickActionResult(route: route, selected: true) }
        let ready = await poll(for: .milliseconds(800)) {
            await shows(path, isSave: isSave, serial: serial, observer: observer)
        }
        guard ready, picker.canConfirm, !Task.isCancelled else {
            return FlixPickActionResult(route: route, selected: true, failure: .notVerified)
        }
        let pressed = await observer.run { $0.confirm(path, isSave: isSave, serial: serial, generation: generation) }
        switch pressed {
        case .done:
            let at = Date.now
            let closed = await poll(for: closeWindow) { !(await observer.run { $0.exists(serial: serial) }) }
            return FlixPickActionResult(route: route, selected: true, confirmed: true, confirmedAt: at,
                                        closedByPress: closed)
        case .gone:
            return FlixPickActionResult(route: route, selected: true, failure: .pickerClosed)
        case .notFrontmost, .secureInput, .modifiersHeld:
            return FlixPickActionResult(route: route, selected: true, failure: .notFrontmost)
        case .notVerified, .unavailable:
            return FlixPickActionResult(route: route, selected: true, failure: .notVerified)
        }
    }

    /// Whether the picker has exactly `path` selected (Open) or lists the rows of that folder
    /// (Save).
    private static func shows(_ path: String, isSave: Bool, serial: Int, observer: FlixPickObserver) async -> Bool {
        if isSave { return await observer.run { $0.folder(path, serial: serial) } == .verified }
        return await observer.run { $0.selection(serial: serial) }.isExactly(path)
    }

    /// Go to Folder. Nil when the sheet opened, took the path, was sent on, and closed.
    private static func goToFolder(_ path: String, picker: FlixPickPicker, generation: Int,
                                   observer: FlixPickObserver) async -> AnalyticsFlixPickFailure? {
        let serial = picker.serial
        guard FlixPickKeys.canType else { return .secureInput }
        guard await FlixPickKeys.waitForModifiersReleased() else { return Task.isCancelled ? .pickerClosed : .modifiersHeld }
        guard !Task.isCancelled else { return .pickerClosed }
        switch await observer.run({ $0.postGoToFolder(serial: serial, generation: generation) }) {
        case .done: break
        case .secureInput: return .secureInput
        case .modifiersHeld: return .modifiersHeld
        case .gone: return .pickerClosed
        case .notFrontmost, .notVerified, .unavailable: return .notFrontmost
        }
        let opened = await poll(for: .milliseconds(1_200)) {
            await observer.run { $0.pathFieldHasFocus(serial: serial) }
        }
        guard opened else { return Task.isCancelled ? .pickerClosed : .noPathField }
        guard !Task.isCancelled, await observer.run({ $0.enterPath(path, serial: serial) }) else {
            await observer.run { $0.dismissGoToFolder(serial: serial) }
            return Task.isCancelled ? .pickerClosed : .noPathField
        }
        switch await observer.run({ $0.submitGoToFolder(path, serial: serial, generation: generation) }) {
        case .done: break
        case .gone: return .pickerClosed
        // Left open with the path typed, for the person to send on.
        default: return .noPathField
        }
        let closed = await poll(for: .milliseconds(1_500)) {
            !(await observer.run { $0.pathFieldHasFocus(serial: serial) })
        }
        guard closed else {
            await observer.run { $0.dismissGoToFolder(serial: serial) }
            return .notVerified
        }
        return nil
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
