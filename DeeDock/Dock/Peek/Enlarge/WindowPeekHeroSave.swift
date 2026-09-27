import AppKit
import OSLog

/// Writes the enlarged preview's picture for the hero toolbar's Save, without a panel.
///
/// With the Shelf tile on, the file goes into the markup folder and is staged on the Shelf, the same
/// as the editor's **Send to Shelf**. Otherwise it goes into Downloads. Either way the user pressed
/// Save, so writing is the explicit action; a failure is reported on the dock and nothing is left
/// behind in the markup folder.
@MainActor
enum WindowPeekHeroSave {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "WindowMarkup")

    /// Where Save goes for a Peek on a dock with `settings`.
    static func target(settings: DockSettings, shelfStaging: Bool) -> WindowPeekHeroSaveTarget {
        settings.showShelf && shelfStaging ? .shelf : .downloads
    }

    /// Saves `image` and returns the tile to fly into, or `nil` after reporting a failure on `panel`.
    ///
    /// - Parameters:
    ///   - title: The window title, used for the file name; `appName` stands in when it is empty.
    ///   - stageOnShelf: Stages a file on the Shelf and returns how many did not fit. Required for `.shelf`.
    ///   - panel: The dock the Peek belongs to. Its tile is the flight's target and its banner shows errors.
    static func save(_ image: CGImage, title: String, appName: String, to target: WindowPeekHeroSaveTarget,
                     settings: DockSettings, stageOnShelf: ((URL) throws -> Int)?,
                     panel: DockPanelController?) -> WindowPeekSavedPicture? {
        let format = settings.windowMarkupFormat
        guard let data = WindowMarkupExport.data(image, format: format) else {
            panel?.store.errorMessage = .markupNoticeSaveFailed
            return nil
        }
        let folder = target == .shelf ? WindowMarkupFolder.url(configured: settings.windowMarkupFolder)
                                      : DownloadsDockItem.folderURL
        let url: URL
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = WindowMarkupExport.uniqueURL(
                in: folder, filename: WindowMarkupExport.suggestedFilename(title: title, appName: appName,
                                                                           at: .now, format: format))
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Enlarged preview not saved: \(error.localizedDescription, privacy: .public)")
            panel?.store.errorMessage = .markupNoticeSaveFailed
            return nil
        }

        let entry: DockEntryID
        let announcement: LocalizedStringResource
        switch target {
        case .shelf:
            do {
                guard let stageOnShelf else { throw CocoaError(.featureUnsupported) }
                if try stageOnShelf(url) > 0 {
                    // The user asked for the Shelf; a file that did not get there would only be clutter.
                    try? FileManager.default.removeItem(at: url)
                    panel?.store.errorMessage = .markupNoticeShelfFull
                    return nil
                }
            } catch {
                logger.error("Enlarged preview not shelved: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: url)
                panel?.store.errorMessage = .markupNoticeShelfFailed
                return nil
            }
            entry = .shelf
            announcement = .markupNoticeShelved
        case .downloads:
            entry = .folder(DownloadsDockItem.id)
            announcement = .markupHeroSavedToDownloads
        }

        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: String(localized: announcement),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return WindowPeekSavedPicture(tile: panel?.tileFrame(for: entry),
                                      arrived: { [weak panel] in panel?.tileReceived(entry) })
    }
}
