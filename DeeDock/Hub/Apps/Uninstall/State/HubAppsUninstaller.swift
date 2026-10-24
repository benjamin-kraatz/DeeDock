import AppKit
import Observation

/// Owns the Apps tab's uninstall sheet: starts a session from the context menu, keeps the Hub open while
/// removal runs, and tidies the dock and launcher once the app is in the Trash.
///
/// ``HubAppsModel`` creates one for the Hub's lifetime and forwards tab visibility and keys.
/// `DockCoordinator` sets ``pinnedDisplayCount`` and ``unpinEverywhere``, which need every connected display's
/// dock. Pins saved for displays that aren't connected stay, like other pins of a missing app.
@MainActor @Observable
final class HubAppsUninstaller {
    /// The session the sheet shows, or nil when no sheet is open.
    private(set) var session: AppUninstallSession?

    /// How many displays' docks pin the app with this DOKK identity.
    @ObservationIgnored var pinnedDisplayCount: ((String) -> Int)?
    /// Removes the app's pin from every connected display's dock.
    @ObservationIgnored var unpinEverywhere: ((String) -> Void)?
    /// Keeps the Hub open across focus loss (`true`) or lets it go (`false`). Set by ``HubAppsModel``.
    @ObservationIgnored var holdHub: ((Bool) -> Void)?
    /// The services new sessions use. Previews replace them.
    @ObservationIgnored var makeServices: ([ApplicationReference]) -> AppUninstallServices = { .live(installed: $0) }

    @ObservationIgnored private let launcher: LauncherState

    init(launcher: LauncherState) {
        self.launcher = launcher
    }

    /// Opens the sheet for `application`, replacing any sheet that isn't removing yet.
    func begin(_ application: ApplicationReference) {
        if let session {
            guard !session.phase.isWorking else { return }
            session.cancel()
        }
        let installed = launcher.library.applications.map(\.reference)
        let session = AppUninstallSession(application: application,
                                          pinnedDisplayCount: pinnedDisplayCount?(application.id) ?? 0,
                                          services: makeServices(installed))
        session.onPhaseChange = { [weak self] phase in self?.holdHub?(phase.isWorking) }
        session.didRemoveApp = { [weak self] session in self?.didRemoveApp(session) }
        self.session = session
    }

    /// Opens the sheet for the app at `url`, after DOKK relaunched for Full Disk Access.
    func begin(appAt url: URL) {
        let name = FileManager.default.displayName(atPath: url.path)
        begin(ApplicationReference(bundleIdentifier: Bundle(url: url)?.bundleIdentifier, url: url,
                                   name: (name as NSString).deletingPathExtension))
    }

    /// Closes the sheet. Ignored while removal runs.
    func end() {
        guard let session, !session.phase.isWorking else { return }
        session.cancel()
        holdHub?(false)
        self.session = nil
    }

    /// The tab became visible again: a removal still running keeps the Hub open.
    func tabDidAppear() {
        if session?.phase.isWorking == true { holdHub?(true) }
    }

    /// The tab or the Hub closed. A session that is removing, or waiting for the user to allow Full Disk
    /// Access, stays for when the Hub opens again; any other closes like Cancel.
    func tabDidDisappear() {
        guard let session else { return }
        if session.phase.isWorking || (session.accessStage == .openedSettings && session.isEditable) { return }
        end()
    }

    /// Handles a key while the sheet shows. Escape cancels and Return takes the default action; other
    /// navigation keys are swallowed so they can't move the selection behind the sheet. Typing still
    /// reaches the search field.
    /// - Returns: Whether the key was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let session else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case 53 where modifiers.isEmpty: // Escape: Cancel, or Done once finished; ignored while removing.
            end()
            return true
        case 36 where modifiers.isEmpty, 76 where modifiers.isEmpty: // Return, keypad Enter
            if case .done = session.phase { end() }
            // An app with a system extension has no default button: its uninstaller comes first.
            else if session.canConfirm, session.target?.hasSystemExtensions == false { session.confirm() }
            return true
        case 123, 124, 125, 126: // Arrows
            return true
        default:
            return false
        }
    }

    /// Opens the Trash in Finder and closes the sheet.
    func showTrash() {
        if let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            NSWorkspace.shared.open(trash)
        }
        end()
    }

    /// Opens the vendor's uninstaller.
    func openVendorUninstaller() {
        guard let url = session?.target?.vendorUninstaller else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens System Settings › General › Login Items & Extensions, where extensions can be removed.
    func openExtensionsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func didRemoveApp(_ session: AppUninstallSession) {
        if session.unpin, session.pinnedDisplayCount > 0 { unpinEverywhere?(session.applicationID) }
        if launcher.favorites.ids.contains(session.applicationID) { launcher.favorites.toggle(session.applicationID) }
        launcher.library.refresh()
    }
}
