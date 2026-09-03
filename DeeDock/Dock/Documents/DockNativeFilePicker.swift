import AppKit

/// A standalone native panel: it must not make the nonactivating dock into a modal-sheet host.
@MainActor
final class DockNativeFilePicker: DockFileChoosing {
    private let panel = NSOpenPanel()

    func present(for reference: ApplicationReference, completion: @escaping ([URL]?) -> Void) {
        panel.title = String(localized: .openFilesPickerTitle(appName: reference.name))
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.canCreateDirectories = false
        NSApp.activate()
        panel.begin { [panel] response in completion(response == .OK ? panel.urls : nil) }
    }

    func bringForward() { NSApp.activate(); panel.makeKeyAndOrderFront(nil) }
    func cancel() { panel.cancel(nil) }
}
