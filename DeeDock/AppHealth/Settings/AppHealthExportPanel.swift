import AppKit
import UniformTypeIdentifiers

/// Asks where to save an App Health export. Nothing is written until the person confirms.
enum AppHealthExportPanel {
    /// Shows a save panel for a `.zip` named `DOKK App Health <date>.zip` and calls `chosen` with the destination.
    /// Not called on cancel.
    static func present(now: Date = .now, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = String(localized: .appHealthExportFileName(
            date: now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))) + ".zip"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { chosen(url) }
        }
    }
}
