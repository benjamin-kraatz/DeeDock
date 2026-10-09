import AppKit
import Observation

/// The Hub's Apps tab: the full launcher (app browsing, mixed search, suggestions, tools, Robi, and
/// file actions) hosted in the Hub instead of the retired dock-morph and popover presentations.
///
/// ## Ownership
/// One model and one ``LauncherState`` exist for the app-wide Hub. App discovery, favorites,
/// history, and suggestions were already app-wide through ``ApplicationCatalog``; what used to be
/// per dock is now handled explicitly:
/// - The source display's pins, line-icon settings, and app visibility arrive through
///   ``present(on:)`` each time the Hub opens.
/// - Browse scroll restoration is remembered per display ID, so reopening on another display
///   does not inherit a foreign offset.
/// - Window discovery is not display-scoped; it lists windows on every display, as before.
///
/// ## Lifecycle
/// ``hubTabDidAppear(shell:)`` begins a launcher presentation (window discovery, a fresh
/// suggestion prediction, app discovery) and ``hubTabDidDisappear()`` ends it, cancelling all of
/// that work. The query and browse options survive tab switches.
@MainActor @Observable
final class HubAppsModel: HubTabModel {
    /// The launcher state this tab presents.
    let launcher: LauncherState

    /// When the tab last appeared. Tiles created shortly after run the staggered entrance; tiles a
    /// lazy grid creates later while scrolling appear without it.
    @ObservationIgnored private(set) var appearedAt = Date.distantPast

    @ObservationIgnored private weak var shell: HubShell?
    @ObservationIgnored private var display: HubAppsDisplayContext?
    @ObservationIgnored private var scrollByDisplay: [String: LauncherBrowseScroll] = [:]
    /// Files handed over before the tab is visible; adopted right after the presentation begins,
    /// because beginning resets file-action mode.
    @ObservationIgnored private var pendingAdoption: LauncherFileAdoption?
    @ObservationIgnored private var holds: Set<Hold> = []
    @ObservationIgnored private var menuObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var trackingMenus: Set<ObjectIdentifier> = []
    /// The window hosting ``HubAppsView``, reported by the view. Menu tracking counts as a Hub
    /// menu only while this window is key.
    @ObservationIgnored weak var hostWindow: NSWindow?

    /// Independent reasons this tab keeps the Hub open, each mapped to one ``HubHoldReason``.
    private enum Hold: Hashable {
        case fileChooser, dialog, menu

        var reason: HubHoldReason {
            switch self {
            case .fileChooser, .dialog: .modal
            case .menu: .menu
            }
        }
    }

    /// Creates the Apps tab around the app-wide launcher state.
    ///
    /// The Hub owner creates the launcher once with `LauncherState(catalog: catalog)` and wires the
    /// app-wide hooks the dock coordinator used to set per panel: `search` (`shelf`, `capsules`,
    /// `actions`, `modes`, `dispatch`, `explicitSearch`), `fileActions.configure(...)`,
    /// `suggestionModeID`, `createCapsule`, and `openTool`. This model owns `close`, `didOpen`,
    /// `dockStore`, `usesLineIcons`, `lineIconMotion`, and `suggestionVisibility`; do not set
    /// those elsewhere.
    /// - Parameter launcher: The single launcher state for the Hub's lifetime.
    init(launcher: LauncherState) {
        self.launcher = launcher
        launcher.suggestionVisibility = { [weak self] in self?.display?.appVisibility ?? .showAll }
    }

    // MARK: - HubTabModel

    var query: String {
        get { launcher.query }
        set { launcher.query = newValue }
    }

    var searchPrompt: LocalizedStringResource {
        launcher.usesFileActions ? .launcherFileSearchPrompt : .launcherSearch
    }

    func hubTabDidAppear(shell: HubShell) {
        self.shell = shell
        launcher.close = { [weak self] in self?.shell?.dismissAfterAction() }
        launcher.didOpen = { [weak self] in self?.shell?.dismissAfterAction() }
        launcher.fileActions.choosingChanged = { [weak self] choosing in self?.setHold(.fileChooser, choosing) }
        launcher.begin(pins: launcher.dockStore?.pins.compactMap(\.application) ?? [],
                       foregroundID: foregroundBundleIdentifier())
        appearedAt = Date()
        if let pendingAdoption {
            self.pendingAdoption = nil
            launcher.adoptFiles(pendingAdoption)
        }
        installMenuObservers()
    }

    func hubTabDidDisappear() {
        removeMenuObservers()
        if let display { scrollByDisplay[display.displayID] = launcher.browseScroll }
        // Ending cancels an open file chooser, which reports `false` through `choosingChanged`.
        launcher.end()
        launcher.fileActions.choosingChanged = nil
        for hold in holds { shell?.endHold(hold.reason) }
        holds = []
        shell = nil
    }

    func handleKeyDown(_ event: NSEvent, fromSearchField: Bool) -> Bool {
        // Input-method candidates own arrows, Return, and Escape until composition ends.
        if fromSearchField, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        // The survey's answer field keeps its keys; Escape leaves it for the search field.
        if launcher.surveyTextFocused {
            guard event.keyCode == KeyCode.escape else { return false }
            shell?.focusSearchField()
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let columns = launcher.usesGridNavigation ? max(1, launcher.navigationColumns) : 1
        switch event.keyCode {
        case KeyCode.escape where modifiers.isEmpty:
            // Robi first, then the keyboard selection; the shell then clears the query or closes.
            if launcher.robiActive { launcher.cancelRobi(); return true }
            if launcher.keyboardNavigationActive { clearKeyboardSelection(); return true }
            return false
        case KeyCode.return, KeyCode.keypadEnter:
            if modifiers.isEmpty { launcher.openSelection(); return true }
            if modifiers == .command { toggleRobi(); return true }
            return false
        case KeyCode.down where modifiers.isEmpty:
            launcher.moveSelection(by: columns); return true
        case KeyCode.up where modifiers.isEmpty:
            launcher.moveSelection(by: -columns); return true
        case KeyCode.left where modifiers.isEmpty, KeyCode.right where modifiers.isEmpty:
            // In the field, left and right move the text cursor until arrow navigation has begun.
            guard !fromSearchField || launcher.keyboardNavigationActive else { return false }
            launcher.moveSelection(by: event.keyCode == KeyCode.left ? -1 : 1); return true
        case KeyCode.tab:
            // Tab leaves result navigation for the native control focus ring.
            clearKeyboardSelection()
            return false
        default:
            return typeIntoSearch(event, fromSearchField: fromSearchField, modifiers: modifiers)
        }
    }

    // MARK: - Shell entry points

    /// Applies the inputs of the display whose dock opened the Hub. Call before or right after the
    /// Hub opens, and again if it reopens on another display.
    func present(on context: HubAppsDisplayContext) {
        if let display, display.displayID != context.displayID {
            scrollByDisplay[display.displayID] = launcher.browseScroll
            launcher.browseScroll = scrollByDisplay[context.displayID]
        } else if display == nil {
            launcher.browseScroll = scrollByDisplay[context.displayID]
        }
        display = context
        launcher.dockStore = context.dockStore
        launcher.usesLineIcons = context.usesLineIcons
        launcher.lineIconMotion = context.lineIconMotion
    }

    /// Enters file-action mode with files dropped on the DOKK tile or handed over from Shelf.
    ///
    /// The shell selects the Apps tab. If the tab is not visible yet, the batch is held and adopted
    /// as soon as it appears; a newer batch replaces a held one.
    func adoptFiles(_ adoption: LauncherFileAdoption) {
        if launcher.isActive { launcher.adoptFiles(adoption) } else { pendingAdoption = adoption }
    }

    // MARK: - View entry points

    /// Keeps the Hub open while a confirmation dialog owned by this tab is showing.
    func setDialogPresented(_ presented: Bool) { setHold(.dialog, presented) }

    /// Drops arrow-key selection, for example after a click, so Return falls back to the first result.
    func clearKeyboardSelection() {
        launcher.keyboardNavigationActive = false
        launcher.selectedID = nil
        launcher.search.selectedID = nil
        launcher.fileActions.selectedID = nil
    }

    /// Asks Robi about the query, or cancels a running request.
    func toggleRobi() {
        guard !launcher.usesFileActions else { return }
        if launcher.robiBusy { launcher.cancelRobi(); return }
        guard !launcher.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              launcher.hasLocationMatchingApplications else { return }
        launcher.askRobi()
    }

    // MARK: - Private

    private func foregroundBundleIdentifier() -> String? {
        if let id = display?.foregroundBundleIdentifier { return id }
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return front?.bundleIdentifier
    }

    /// Printable keys typed while results have focus go to the header field, like the system's
    /// type-to-search lists.
    private func typeIntoSearch(_ event: NSEvent, fromSearchField: Bool,
                                modifiers: NSEvent.ModifierFlags) -> Bool {
        guard !fromSearchField, modifiers.subtracting(.shift).isEmpty,
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                  && $0.value < 0xF700 }) else { return false }
        launcher.query += characters
        shell?.focusSearchField()
        return true
    }

    private func setHold(_ hold: Hold, _ active: Bool) {
        if active {
            guard holds.insert(hold).inserted else { return }
            shell?.beginHold(hold.reason)
        } else {
            guard holds.remove(hold) != nil else { return }
            shell?.endHold(hold.reason)
        }
    }

    /// SwiftUI context menus and `Menu` buttons report no open/close events, so menu tracking is
    /// observed app-wide while the tab is visible and attributed to the Hub only when its window
    /// is key. Begin/end pairs are counted per menu so nested submenus cannot release early.
    private func installMenuObservers() {
        guard menuObservers.isEmpty else { return }
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                                queue: .main) { [weak self] notification in
            let id = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let id, let hostWindow = self.hostWindow, NSApp.keyWindow === hostWindow else { return }
                self.trackingMenus.insert(id)
                self.setHold(.menu, true)
            }
        })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil,
                                                queue: .main) { [weak self] notification in
            let id = (notification.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let id, self.trackingMenus.remove(id) != nil else { return }
                if self.trackingMenus.isEmpty { self.setHold(.menu, false) }
            }
        })
    }

    private func removeMenuObservers() {
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers = []
        trackingMenus = []
        setHold(.menu, false)
    }

    /// Virtual key codes the tab handles (layout-independent).
    private enum KeyCode {
        static let `return`: UInt16 = 36
        static let tab: UInt16 = 48
        static let escape: UInt16 = 53
        static let keypadEnter: UInt16 = 76
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }
}
