import Foundation

/// The Tidy sheet's suggestions: better names for cryptic files and folders for downloads, made
/// from the annotations already shown on the rows. No file is read and nothing is asked, so the
/// sheet fills at once; whether each file is still there is checked off the main actor.
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
        var candidates: [(suggestion: FlixTidySuggestion, path: String)] = []
        for item in items {
            guard let path = item.path, item.kind != .folder, item.kind != .app, item.kind != .link,
                  let annotation = annotations[item.id], annotation.isNoise != true,
                  !FlixNoiseRules.isNoise(path: path), policy.spellingIsReadable(path) else { continue }
            let rename = settings.writesCaptions && FlixFileNaming.isCryptic(item.name)
                ? annotation.renameSuggestion : nil
            let move = settings.suggestsFolders && (path as NSString).deletingLastPathComponent == downloads
                ? annotation.folderSuggestion : nil
            guard rename != nil || move != nil else { continue }
            candidates.append((FlixTidySuggestion(itemID: item.id, rename: rename, moveTo: move), path))
        }
        let present = await Self.present(candidates.map(\.path), policy: policy, limit: Self.limit)
        return candidates.filter { present.contains($0.path) }.prefix(Self.limit).map(\.suggestion)
    }

    /// The first `limit` of `paths`, in order, that the policy allows and that still exist. Off the
    /// main actor: the policy's check and the existence check both touch the disk.
    @concurrent private static func present(_ paths: [String], policy: FlixReadPolicy, limit: Int) async -> Set<String> {
        var found = Set<String>()
        for path in paths where found.count < limit {
            guard !Task.isCancelled else { break }
            if policy.canRead(path), FileManager.default.fileExists(atPath: path) { found.insert(path) }
        }
        return found
    }
}
