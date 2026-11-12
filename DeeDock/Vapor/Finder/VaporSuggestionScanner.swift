import Foundation

/// A folder Finder is showing that Vapor could take.
nonisolated struct VaporSuggestion: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    let url: URL
    let tag: VaporTag

    var name: String { url.lastPathComponent }
}

/// Lists a folder's direct children and keeps those matching a suggested rule.
///
/// Synchronous and file-system bound: call it off the main actor. It checks cancellation
/// between children. Hidden children count (`.next`, `.gradle`), packages and links don't.
nonisolated enum VaporSuggestionScanner {
    static func scan(_ folder: URL, home: URL) -> [VaporSuggestion] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                          options: []) else { return [] }
        var found: [VaporSuggestion] = []
        for child in children {
            if Task.isCancelled { return [] }
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
                  values.isPackage != true, values.isSymbolicLink != true,
                  let tag = VaporClassifier.tag(for: child, home: home), tag.isSuggested else { continue }
            found.append(VaporSuggestion(url: child, tag: tag))
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
