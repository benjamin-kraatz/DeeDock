import Foundation

/// The Tidy sheet's suggestions: better names for cryptic files and folders for downloads, made
/// from the annotations already shown on the rows. Nothing is read or asked here, so the sheet fills
/// at once.
///
/// An item is suggested when its name is still cryptic and it has a rename suggestion (captions on),
/// or it still sits directly in Downloads and has a folder suggestion (folder suggestions on).
/// Noise, folders, apps, links, and files that are gone are left out; at most ``limit``, newest first.
/// Applying goes through `FlixPanelState.applyTidy`, which renames, then moves, with one Undo.
@MainActor
final class FlixTidyProvider: FlixTidyProviding {
    static let limit = 30
    private let services: FlixSmartServices

    init(services: FlixSmartServices) {
        self.services = services
    }

    func suggestions(for items: [FlixItem], annotations: [FlixItem.ID: FlixItemAnnotation]) async -> [FlixTidySuggestion] {
        let settings = services.settings
        let policy = services.readPolicy
        let downloads = FlixPaths.downloads()
        var result: [FlixTidySuggestion] = []
        for item in items where result.count < Self.limit {
            guard let path = item.path, item.kind != .folder, item.kind != .app, item.kind != .link,
                  let annotation = annotations[item.id], annotation.isNoise != true,
                  !FlixNoiseRules.isNoise(path: path), policy.canRead(path),
                  FileManager.default.fileExists(atPath: path) else { continue }
            let rename = settings.writesCaptions && FlixFileNaming.isCryptic(item.name)
                ? annotation.renameSuggestion : nil
            let move = settings.suggestsFolders && (path as NSString).deletingLastPathComponent == downloads
                ? annotation.folderSuggestion : nil
            guard rename != nil || move != nil else { continue }
            result.append(FlixTidySuggestion(itemID: item.id, rename: rename, moveTo: move))
        }
        return result
    }
}
