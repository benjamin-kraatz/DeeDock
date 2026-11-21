import ApplicationServices
import Foundation
import Synchronization

/// What reading the picker's selection back found.
nonisolated enum FlixPickReadback: Equatable, Sendable {
    /// The picker is gone.
    case gone
    /// No list view to read (column or icon view).
    case unavailable
    /// How many rows are selected, and the file when exactly one is.
    case selected(count: Int, url: URL?)

    /// Exactly `path` is selected, nothing else.
    func isExactly(_ path: String) -> Bool {
        guard case .selected(1, let url?) = self else { return false }
        return FlixPickAX.same(url, path)
    }
}

/// Whether the picker shows a folder, by the place its listed rows are in.
nonisolated enum FlixPickFolderCheck: Equatable, Sendable {
    case verified
    case elsewhere
    /// Nothing listed to tell from (an empty folder, or no list view).
    case unknown
    case gone
}

/// What selecting a file among the rows the picker lists found.
nonisolated enum FlixPickListedResult: Equatable, Sendable {
    case selected
    /// Not among the listed rows (another folder, or too many rows to look through).
    case notListed
    /// No list view, or the selection could not be set.
    case unavailable
    case gone
}

/// Why an action that needs the picker in front did not run.
nonisolated enum FlixPickGuardResult: Equatable, Sendable {
    case done
    case secureInput
    case modifiersHeld
    /// Another app or window is in front, or the frontmost app changed since the action began.
    case notFrontmost
    /// The picker's selection or folder is not exactly what was asked for.
    case notVerified
    /// The control is disabled or offers no action.
    case unavailable
    case gone
}

/// Flix Pick's Accessibility state for the frontmost app: one `AXObserver`, the picker that has
/// focus, and the picker's controls.
///
/// Confined to ``FlixAXThread``: every method except ``advance()`` and ``generation`` runs there,
/// called through `FlixPickObserver`. The elements never leave the thread; the main actor hears
/// about the picker through ``FlixPickEvent`` values, delivered in order with
/// `DispatchQueue.main`, and names it by its serial in every operation.
///
/// **Detection.** On the app element: `kAXWindowCreatedNotification`,
/// `kAXFocusedWindowChangedNotification`, `kAXMainWindowChangedNotification`, and `AXSheetCreated`.
/// Each burst is coalesced for a few milliseconds, then the focused window is checked for a picker
/// (``FlixPickAX/picker(in:)``). While a picker has focus, it adds `kAXUIElementDestroyedNotification`,
/// `kAXMovedNotification`, and `kAXResizedNotification` on the picker (and on its window when it
/// is a sheet), `kAXSelectedRowsChangedNotification` on the picker and its list, `kAXValueChangedNotification`
/// on the folder popup, and `kAXFocusedUIElementChangedNotification` on the app, which notices a
/// sheet that closed without being destroyed. No polling.
///
/// **Ownership.** The observer's run-loop source lives on the thread's run loop. ``detach(generation:)``
/// removes every notification and the source on the thread, so no callback can arrive after it;
/// the callback's `refcon` is this session, unretained, and the session outlives the observer.
nonisolated final class FlixPickSession: @unchecked Sendable {
    private let latest = Mutex(0)
    /// Set once on the main actor before the first attach; read on the thread.
    var deliver: (@MainActor @Sendable (FlixPickEvent) -> Void)?

    // MARK: Thread-confined state

    /// The picker with focus and what was found inside it.
    nonisolated private final class Picker {
        let element: AXUIElement
        /// The document window a sheet is attached to.
        let parent: AXUIElement?
        let kind: FlixPickPickerKind
        let serial: Int
        var controls: [String: AXUIElement] = [:]
        var buttonTitle: String?
        var registered: [(element: AXUIElement, name: String)] = []
        var rediscovered = false
        /// The controls' frames and the picker's frame when they were read. A move shifts them by
        /// the picker's offset instead of reading them again; a resize reads them again.
        var controlFrames: (confirm: CGRect?, cancel: CGRect?, list: CGRect?) = (nil, nil, nil)
        var framesReadAt: CGRect = .zero

        init(element: AXUIElement, parent: AXUIElement?, kind: FlixPickPickerKind, serial: Int) {
            self.element = element
            self.parent = parent
            self.kind = kind
            self.serial = serial
        }
    }

    private var observer: AXObserver?
    private var app: AXUIElement?
    private var pid: pid_t = 0
    private var current: Picker?
    private var serialCounter = 0
    /// The last picker that lost focus without going away, so it keeps its serial when it returns.
    private var previous: (element: AXUIElement, serial: Int)?
    private var evaluateTimer: CFRunLoopTimer?

    private static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                           kAXMainWindowChangedNotification, "AXSheetCreated"]

    var generation: Int { latest.withLock { $0 } }

    /// Starts a new generation; attach and detach work queued for an older one is skipped.
    @discardableResult
    func advance() -> Int { latest.withLock { $0 += 1; return $0 } }

    private func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

    // MARK: Attaching

    func attach(to pid: pid_t, generation: Int) {
        guard isCurrent(generation) else { return }
        if pid == self.pid, observer != nil {
            scheduleEvaluate(after: 0)
            return
        }
        removeObserver()
        guard AXIsProcessTrusted(), isCurrent(generation) else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, FlixPickAX.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications { AXObserverAddNotification(created, element, name as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        app = element
        self.pid = pid
        evaluate()
    }

    func detach(generation: Int) {
        guard isCurrent(generation) else { return }
        removeObserver()
    }

    /// Removes every notification and the run-loop source. A picker that had focus is reported
    /// closed (not destroyed): its app moved to the back.
    private func removeObserver() {
        if let current {
            unregister(current)
            post(.closed(serial: current.serial, destroyed: false))
            previous = (current.element, current.serial)
            self.current = nil
        }
        if let evaluateTimer { CFRunLoopTimerInvalidate(evaluateTimer) }
        evaluateTimer = nil
        if let observer {
            if let app {
                for name in Self.appNotifications { AXObserverRemoveNotification(observer, app, name as CFString) }
            }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        app = nil
        pid = 0
    }

    // MARK: Following the picker

    private func scheduleEvaluate(after delay: CFTimeInterval) {
        guard evaluateTimer == nil else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { [weak self] _ in
            self?.evaluateTimer = nil
            self?.evaluate()
        }
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        evaluateTimer = timer
    }

    /// Checks the focused window for a picker and reports what changed.
    private func evaluate() {
        guard let app, observer != nil else { return }
        let found = FlixPickAX.element(app, kAXFocusedWindowAttribute).flatMap(FlixPickAX.picker(in:))
        if let current {
            if let found, CFEqual(found.element, current.element) {
                refresh(current)
                return
            }
            close(current, destroyed: !FlixPickAX.isAlive(current.element))
        }
        guard let found else { return }
        let returning = previous.map { CFEqual($0.element, found.element) } ?? false
        let serial: Int
        if returning, let previous {
            serial = previous.serial
        } else {
            serialCounter += 1
            serial = serialCounter
        }
        previous = nil
        let picker = Picker(element: found.element, parent: found.parent, kind: found.kind, serial: serial)
        current = picker
        register(picker)
        discoverControls(picker)
        post(.appeared(snapshot(picker), returning: returning))
        if picker.controls[FlixPickAX.okButton] == nil || picker.controls[FlixPickAX.listView] == nil {
            // The picker may still be building its controls; look once more shortly, on this run loop.
            let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.3, 0, 0, 0) { [weak self] _ in
                self?.retryDiscovery(serial: serial)
            }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
        }
    }

    private func retryDiscovery(serial: Int) {
        guard let current, current.serial == serial, !current.rediscovered else { return }
        current.rediscovered = true
        discoverControls(current)
        post(.changed(snapshot(current)))
    }

    private func refresh(_ picker: Picker) {
        let title = picker.controls[FlixPickAX.okButton].flatMap { FlixPickAX.string($0, kAXTitleAttribute) }
        guard title != picker.buttonTitle else { return }
        picker.buttonTitle = title
        post(.changed(snapshot(picker)))
    }

    private func close(_ picker: Picker, destroyed: Bool) {
        unregister(picker)
        post(.closed(serial: picker.serial, destroyed: destroyed))
        previous = destroyed ? nil : (picker.element, picker.serial)
        if current === picker { current = nil }
    }

    private func discoverControls(_ picker: Picker) {
        for (element, name) in picker.registered where name == kAXSelectedRowsChangedNotification
            || name == kAXValueChangedNotification || (name == kAXUIElementDestroyedNotification && !CFEqual(element, picker.element)) {
            if let observer { AXObserverRemoveNotification(observer, element, name as CFString) }
        }
        picker.registered.removeAll { entry in
            entry.name == kAXSelectedRowsChangedNotification || entry.name == kAXValueChangedNotification
                || (entry.name == kAXUIElementDestroyedNotification && !CFEqual(entry.element, picker.element))
        }
        picker.controls = FlixPickAX.controls(in: picker.element)
        picker.buttonTitle = picker.controls[FlixPickAX.okButton].flatMap { FlixPickAX.string($0, kAXTitleAttribute) }
        readControlFrames(picker)
        add(kAXSelectedRowsChangedNotification, on: picker.element, for: picker)
        if let list = picker.controls[FlixPickAX.listView] {
            add(kAXSelectedRowsChangedNotification, on: list, for: picker)
            add(kAXUIElementDestroyedNotification, on: list, for: picker)
        }
        if let popup = picker.controls[FlixPickAX.wherePopup] { add(kAXValueChangedNotification, on: popup, for: picker) }
    }

    private func register(_ picker: Picker) {
        add(kAXUIElementDestroyedNotification, on: picker.element, for: picker)
        for element in [picker.element] + (picker.parent.map { [$0] } ?? []) {
            add(kAXMovedNotification, on: element, for: picker)
            add(kAXResizedNotification, on: element, for: picker)
        }
        if let app { add(kAXFocusedUIElementChangedNotification, on: app, for: picker) }
    }

    private func add(_ name: String, on element: AXUIElement, for picker: Picker) {
        guard let observer else { return }
        AXUIElementSetMessagingTimeout(element, FlixPickAX.messagingTimeout)
        let result = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        if result == .success || result == .notificationAlreadyRegistered { picker.registered.append((element, name)) }
    }

    private func unregister(_ picker: Picker) {
        if let observer {
            for (element, name) in picker.registered { AXObserverRemoveNotification(observer, element, name as CFString) }
        }
        picker.registered = []
    }

    private func readControlFrames(_ picker: Picker) {
        let list = picker.controls[FlixPickAX.listView] ?? picker.controls[FlixPickAX.columnView]
        picker.controlFrames = (picker.controls[FlixPickAX.okButton].flatMap(FlixPickAX.frame),
                                picker.controls[FlixPickAX.cancelButton].flatMap(FlixPickAX.frame),
                                list.flatMap(FlixPickAX.visibleFrame(ofList:)))
        picker.framesReadAt = FlixPickAX.frame(picker.element) ?? .zero
    }

    private func snapshot(_ picker: Picker) -> FlixPickPicker {
        let frame = FlixPickAX.frame(picker.element) ?? .zero
        let dx = frame.minX - picker.framesReadAt.minX, dy = frame.minY - picker.framesReadAt.minY
        let shift = { (rect: CGRect?) in rect?.offsetBy(dx: dx, dy: dy) }
        return FlixPickPicker(serial: picker.serial, processIdentifier: pid, kind: picker.kind,
                              isSheet: picker.parent != nil, frame: frame, buttonTitle: picker.buttonTitle,
                              canConfirm: picker.controls[FlixPickAX.okButton] != nil,
                              hasListView: picker.controls[FlixPickAX.listView] != nil,
                              confirmFrame: shift(picker.controlFrames.confirm),
                              cancelFrame: shift(picker.controlFrames.cancel), listFrame: shift(picker.controlFrames.list))
    }

    private func notified(_ element: AXUIElement, _ name: String) {
        guard observer != nil else { return }
        switch name {
        case kAXUIElementDestroyedNotification:
            guard let current else { return }
            if CFEqual(element, current.element) {
                close(current, destroyed: true)
                scheduleEvaluate(after: 0.05)
            } else if let list = current.controls[FlixPickAX.listView], CFEqual(element, list) {
                // The view mode changed; find the list again when it is needed.
                current.controls[FlixPickAX.listView] = nil
            }
        case kAXMovedNotification, kAXResizedNotification:
            guard let current else { return }
            if name == kAXResizedNotification { readControlFrames(current) }
            post(.changed(snapshot(current)))
        case kAXSelectedRowsChangedNotification:
            guard let current else { return }
            let isList = current.controls[FlixPickAX.listView].map { CFEqual($0, element) } ?? false
            guard isList || FlixPickAX.identifier(element) == FlixPickAX.listView else { return }
            AXUIElementSetMessagingTimeout(element, FlixPickAX.messagingTimeout)
            // A file only when exactly one is selected: several selected files are no one choice.
            post(.selection(serial: current.serial,
                            url: FlixPickAX.selection(in: element, deadline: FlixPickAX.Deadline(seconds: 0.3)).url))
        case kAXValueChangedNotification:
            guard let current, let popup = current.controls[FlixPickAX.wherePopup], CFEqual(element, popup) else { return }
            post(.folderChanged(serial: current.serial, name: FlixPickAX.string(popup, kAXValueAttribute)))
        case kAXWindowCreatedNotification, "AXSheetCreated":
            scheduleEvaluate(after: 0.06)
        default:
            scheduleEvaluate(after: 0.02)
        }
    }

    private func post(_ event: FlixPickEvent) {
        let deliver = deliver
        DispatchQueue.main.async { MainActor.assumeIsolated { deliver?(event) } }
    }

    /// The AX callback runs on ``FlixAXThread``'s run loop, where the source was added. `refcon` is
    /// this session, unretained (see the type's notes).
    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        Unmanaged<FlixPickSession>.fromOpaque(refcon).takeUnretainedValue().notified(element, notification as String)
    }

    // MARK: Operations (each one short block on the thread)

    /// The picker with `serial`, while it still exists and has focus in its app.
    private func live(_ serial: Int) -> Picker? {
        guard let current, current.serial == serial, FlixPickAX.isAlive(current.element) else { return nil }
        return current
    }

    /// Finds the controls again when the list went away (a view mode change) or a control is missing.
    private func ensureControls(_ picker: Picker) {
        let listAlive = picker.controls[FlixPickAX.listView].map(FlixPickAX.isAlive) ?? false
        if !listAlive || picker.controls[FlixPickAX.okButton] == nil { discoverControls(picker) }
    }

    /// The app with keyboard focus, from the system-wide element.
    private func focusedPID() -> pid_t? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = RobiAX.element(system, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(focused, &pid) == .success ? pid : nil
    }

    /// The last checks before an irreversible action (a posted key, `AXConfirm`, an `AXPress`),
    /// made after every other read so nothing is read between them and the action: the
    /// attachment the action started under is unchanged, and the picker's app still holds
    /// keyboard focus. Callers check the picker's focus and the exact selection, folder, or field
    /// value just before this.
    private func stillInFront(_ generation: Int) -> Bool {
        isCurrent(generation) && focusedPID() == pid
    }

    private func focused(_ picker: Picker) -> Bool {
        guard let app, let window = FlixPickAX.element(app, kAXFocusedWindowAttribute),
              let found = FlixPickAX.picker(in: window) else { return false }
        return CFEqual(found.element, picker.element)
    }

    /// Selects `path` in place when the picker lists it, replacing any other selection. The first
    /// row says which folder is listed, so a file elsewhere is answered at once; at most 300 rows
    /// are looked through, within 0.8 seconds.
    func selectListed(_ path: String, serial: Int) -> FlixPickListedResult {
        guard let picker = live(serial) else { return .gone }
        ensureControls(picker)
        guard let list = picker.controls[FlixPickAX.listView] else { return .unavailable }
        let deadline = FlixPickAX.Deadline(seconds: 0.8)
        guard let rows = FlixPickAX.elements(list, kAXRowsAttribute), let first = rows.first else { return .notListed }
        guard rows.count <= 300, let firstURL = FlixPickAX.url(ofRow: first, deadline: deadline),
              FlixPickAX.same(firstURL.deletingLastPathComponent(), (path as NSString).deletingLastPathComponent)
        else { return .notListed }
        for row in rows {
            guard !deadline.passed else { return .notListed }
            guard let url = FlixPickAX.url(ofRow: row, deadline: deadline), FlixPickAX.same(url, path) else { continue }
            let result = AXUIElementSetAttributeValue(list, kAXSelectedRowsAttribute as CFString, [row] as CFArray)
            return result == .success ? .selected : .unavailable
        }
        return .notListed
    }

    /// The list's selection now.
    func selection(serial: Int) -> FlixPickReadback {
        guard let picker = live(serial) else { return .gone }
        ensureControls(picker)
        guard let list = picker.controls[FlixPickAX.listView] else { return .unavailable }
        let selected = FlixPickAX.selection(in: list, deadline: FlixPickAX.Deadline(seconds: 0.5))
        return .selected(count: selected.count, url: selected.url)
    }

    /// Whether the picker shows `folder`, by the folder its first listed row is in. An empty folder
    /// is `unknown`: its name in the folder popup is never taken as proof of its place.
    func folder(_ folder: String, serial: Int) -> FlixPickFolderCheck {
        guard let picker = live(serial) else { return .gone }
        ensureControls(picker)
        guard let list = picker.controls[FlixPickAX.listView],
              let shown = FlixPickAX.listedFolder(in: list, deadline: FlixPickAX.Deadline(seconds: 0.5))
        else { return .unknown }
        return FlixPickAX.same(shown, folder) ? .verified : .elsewhere
    }

    /// Whether the picker still has focus in its app.
    func hasFocus(serial: Int) -> Bool {
        guard let picker = live(serial) else { return false }
        return focused(picker)
    }

    /// Posts ⇧⌘G, the one keystroke with no Accessibility alternative, after checking in the same
    /// block, immediately before posting: the attachment, the picker, its app with keyboard focus,
    /// the picker focused, no modifier held, and Secure Event Input off.
    func postGoToFolder(serial: Int, generation: Int) -> FlixPickGuardResult {
        guard isCurrent(generation) else { return .notFrontmost }
        guard let picker = live(serial) else { return .gone }
        guard focused(picker) else { return .notFrontmost }
        guard stillInFront(generation) else { return .notFrontmost }
        guard FlixPickKeys.canType else { return .secureInput }
        guard !FlixPickKeys.modifiersHeld else { return .modifiersHeld }
        FlixPickKeys.press(FlixPickKeys.goToFolderKey, flags: [.maskShift, .maskCommand])
        return .done
    }

    /// The focused element when it is the Go to Folder field of this picker: identifier
    /// `PathTextField`, inside the picker (or its window). Nothing else is ever written.
    private func pathField(of picker: Picker) -> AXUIElement? {
        guard let app, let focused = FlixPickAX.element(app, kAXFocusedUIElementAttribute),
              FlixPickAX.identifier(focused) == FlixPickAX.pathField else { return nil }
        let deadline = FlixPickAX.Deadline(seconds: 0.3)
        var ancestor: AXUIElement? = focused
        for _ in 0..<12 {
            guard let element = ancestor, !deadline.passed else { break }
            if CFEqual(element, picker.element) || picker.parent.map({ CFEqual(element, $0) }) == true { return focused }
            ancestor = FlixPickAX.element(element, kAXParentAttribute)
        }
        return nil
    }

    func pathFieldHasFocus(serial: Int) -> Bool {
        guard let picker = live(serial) else { return false }
        return pathField(of: picker) != nil
    }

    /// Types `path` into the Go to Folder field by setting its value.
    func enterPath(_ path: String, serial: Int) -> Bool {
        guard let picker = live(serial), let field = pathField(of: picker) else { return false }
        return AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, path as CFString) == .success
    }

    /// Sends the Go to Folder sheet on, preferring the field or the sheet itself: the field's
    /// `AXConfirm`, else the sheet's default button when it is not the picker's `OKButton`, else
    /// Return, as the probe proved works. The way is chosen first; then, with nothing else read in
    /// between, every one of them is preceded by the same final checks: the picker focused, the
    /// app's focused element still this picker's `PathTextField` holding exactly `path`, the
    /// attachment unchanged, and the picker's app holding keyboard focus (and for Return, no
    /// modifier held and Secure Event Input off). When any fails, the sheet is left as it is with
    /// the path typed (`unavailable`). Escape is never posted.
    func submitGoToFolder(_ path: String, serial: Int, generation: Int) -> FlixPickGuardResult {
        guard isCurrent(generation) else { return .notFrontmost }
        guard let picker = live(serial) else { return .gone }
        guard let field = pathField(of: picker) else { return .unavailable }
        enum Way { case confirm, button(AXUIElement), returnKey }
        let way: Way
        if FlixPickAX.actions(field).contains(kAXConfirmAction as String) {
            way = .confirm
        } else if let sheet = FlixPickAX.goToSheet(of: field, picker: picker.element),
                  let button = FlixPickAX.element(sheet, kAXDefaultButtonAttribute),
                  FlixPickAX.identifier(button) != FlixPickAX.okButton {
            way = .button(button)
        } else {
            way = .returnKey
        }
        // Final checks, then the action, with no other read in between.
        guard focused(picker), let app, let focusedNow = FlixPickAX.element(app, kAXFocusedUIElementAttribute),
              CFEqual(focusedNow, field), FlixPickAX.string(field, kAXValueAttribute) == path,
              stillInFront(generation) else { return .unavailable }
        switch way {
        case .confirm:
            return AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success ? .done : .unavailable
        case .button(let button):
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success ? .done : .unavailable
        case .returnKey:
            guard FlixPickKeys.canType, !FlixPickKeys.modifiersHeld else { return .unavailable }
            FlixPickKeys.press(FlixPickKeys.returnKey)
            return .done
        }
    }

    /// Closes the Go to Folder sheet the same way: the field's `AXCancel`, else the sheet's cancel
    /// button when it is not the picker's `CancelButton`. Does nothing when neither exists, so the
    /// picker itself is never cancelled.
    func dismissGoToFolder(serial: Int) {
        guard let picker = live(serial), let field = pathField(of: picker) else { return }
        if FlixPickAX.actions(field).contains(kAXCancelAction as String) {
            _ = AXUIElementPerformAction(field, kAXCancelAction as CFString)
            return
        }
        guard let sheet = FlixPickAX.goToSheet(of: field, picker: picker.element),
              let button = FlixPickAX.element(sheet, kAXCancelButtonAttribute),
              FlixPickAX.identifier(button) != FlixPickAX.cancelButton else { return }
        _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Presses `OKButton`. Discovery and the button's enabled state are read first; then, with
    /// nothing else read in between, the final checks: the picker focused, exactly `path` selected
    /// (Open) or the picker's listed rows inside `path` (Save), the attachment the action started
    /// under unchanged, and the picker's app holding keyboard focus. `done` only when the press
    /// went through.
    func confirm(_ path: String, isSave: Bool, serial: Int, generation: Int) -> FlixPickGuardResult {
        guard isCurrent(generation) else { return .notFrontmost }
        guard let picker = live(serial) else { return .gone }
        ensureControls(picker)
        guard let list = picker.controls[FlixPickAX.listView] else { return .notVerified }
        guard let ok = picker.controls[FlixPickAX.okButton],
              (RobiAX.value(ok, kAXEnabledAttribute) as? Bool) ?? false else { return .unavailable }
        // Final checks, then the press, with no other read in between.
        guard focused(picker) else { return .notFrontmost }
        let deadline = FlixPickAX.Deadline(seconds: 0.5)
        if isSave {
            guard let shown = FlixPickAX.listedFolder(in: list, deadline: deadline), FlixPickAX.same(shown, path)
            else { return .notVerified }
        } else {
            let selected = FlixPickAX.selection(in: list, deadline: deadline)
            guard selected.count == 1, let url = selected.url, FlixPickAX.same(url, path) else { return .notVerified }
        }
        guard stillInFront(generation) else { return .notFrontmost }
        return AXUIElementPerformAction(ok, kAXPressAction as CFString) == .success ? .done : .unavailable
    }

    /// Whether the picker still exists and has focus in its app, for telling whether a press
    /// closed it.
    func exists(serial: Int) -> Bool { live(serial) != nil }
}
