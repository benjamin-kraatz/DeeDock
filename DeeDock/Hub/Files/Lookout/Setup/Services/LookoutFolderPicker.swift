import AppKit

/// Lets the person pick a folder for Lookout. Picking one in the panel is their consent to Lookout reading it.
@MainActor protocol LookoutFolderPicking: AnyObject {
    /// Shows the picker and waits; nil when cancelled.
    func pickFolder() async -> URL?
}

/// `NSOpenPanel`, limited to one folder. DOKK is an agent app whose Hub is a nonactivating panel, so the app is
/// activated first, as the Launcher's file chooser does, or the panel would open behind the frontmost app. Callers
/// keep an anchored Hub open while it shows (`HubHoldReason.modal`): the panel takes key status from the Hub.
@MainActor final class LookoutOpenPanelPicker: LookoutFolderPicking {
    private var panel: NSOpenPanel?

    func pickFolder() async -> URL? {
        if let panel {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            return nil
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: .lookoutPickerTitle)
        panel.prompt = String(localized: .lookoutPickerPrompt)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        self.panel = panel
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        self.panel = nil
        return response == .OK ? panel.url : nil
    }
}

/// A picker that answers without showing anything: previews and tests.
@MainActor final class LookoutStubFolderPicker: LookoutFolderPicking {
    var next: URL?

    init(next: URL? = nil) { self.next = next }

    func pickFolder() async -> URL? { next }
}

/// Opens System Settings at Privacy & Security › Files and Folders, where the person can let DOKK read a folder they
/// declined. Falls back to System Settings' root when macOS doesn't take the pane's address. Never changes a setting.
enum LookoutPrivacySettings {
    static let filesAndFolders = URL(string:
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders")

    static func openFilesAndFolders() {
        if let url = filesAndFolders, NSWorkspace.shared.open(url) { return }
        SystemSettingsDeepLinkOpener.openRoot()
    }
}
