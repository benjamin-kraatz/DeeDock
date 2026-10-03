import AppKit

/// The hard-disk question as a system alert, for the rare eject whose tile is scrolled out of view
/// and so has no card to ask in.
enum VolumeEjectAlert {
    /// Returns true when the user chose Eject.
    static func confirmDisk(named name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: .volumeConfirmDiskTitle(name: name))
        alert.informativeText = String(localized: .volumeConfirmDiskMessage)
        alert.addButton(withTitle: String(localized: .volumeEject)).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .volumeCancel))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
