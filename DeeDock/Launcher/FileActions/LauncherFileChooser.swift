import AppKit

/// Native file and folder panels for Launcher file actions. A nil response is cancellation.
///
/// The panel references are stored before `begin()`, so `isChoosing` is true before the
/// first click can reach the launcher's outside-click monitors.
@MainActor
final class LauncherFileChooser {
    private var fileToken: UUID?
    private var folderToken: UUID?
    private var filePanel: NSOpenPanel?
    private var folderPanel: NSOpenPanel?

    var isChoosing: Bool { filePanel != nil || folderPanel != nil }

    /// Returns whether `window` is this chooser's in-process file or folder panel.
    func owns(_ window: NSWindow) -> Bool {
        window === filePanel || window === folderPanel
    }

    func chooseFiles(completion: @escaping ([URL]?) -> Void) {
        if let filePanel {
            NSApp.activate()
            filePanel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: .launcherFileChooseFilesTitle)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.canCreateDirectories = false
        let token = UUID()
        fileToken = token
        filePanel = panel
        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, fileToken == token else { return }
            filePanel = nil
            fileToken = nil
            completion(response == .OK ? panel.urls : nil)
        }
    }

    func chooseFolder(completion: @escaping (URL?) -> Void) {
        if let folderPanel {
            NSApp.activate()
            folderPanel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: .launcherFileChooseFolderTitle)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        let token = UUID()
        folderToken = token
        folderPanel = panel
        NSApp.activate()
        panel.begin { [weak self] response in
            guard let self, folderToken == token else { return }
            folderPanel = nil
            folderToken = nil
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// Drops tokens before cancelling AppKit so a synchronous callback cannot adopt a stale batch.
    func cancel() {
        let file = filePanel
        let folder = folderPanel
        fileToken = nil
        folderToken = nil
        filePanel = nil
        folderPanel = nil
        file?.cancel(nil)
        folder?.cancel(nil)
    }
}
