import AppKit

/// One row of the handoff panel's list: what the user recognizes about a staged file.
///
/// Icons come from `NSWorkspace`, which resolves them from the file's type rather than its
/// contents, so a batch is resolved once when the panel opens and the scrolling list stays free of
/// per-frame lookups. Nothing here reads or opens the file.
struct WindowFileHandoffFile: Identifiable {
    let url: URL
    let name: String
    /// Enclosing folder name, shown exactly as the file system supplies it and never localized.
    let location: String
    let icon: NSImage

    var id: URL { url }

    @MainActor init(url: URL) {
        self.url = url
        name = url.lastPathComponent
        location = url.deletingLastPathComponent().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        self.icon = icon
    }
}
