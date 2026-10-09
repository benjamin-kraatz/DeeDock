import Foundation

/// Finder-style names that never collide with existing items.
nonisolated enum HubFileNaming {
    /// Returns `name` when it is free in `folder`, else Finder's copy name.
    ///
    /// "Report.pdf" becomes "Report copy.pdf", then "Report copy 2.pdf". Folders and names
    /// without an extension get "Folder copy", "Folder copy 2". A name that already ends in
    /// "copy" or "copy N" continues the sequence instead of stacking ("Report copy copy").
    /// - Parameter fileExists: Collision check, injected so tests need no disk.
    static func availableName(for name: String, in folder: URL, fileExists: (URL) -> Bool) -> String {
        let candidate = folder.appendingPathComponent(name)
        guard fileExists(candidate) else { return name }
        let (stem, ext) = split(name)
        let suffix = String(localized: .hubFilesCopySuffix)
        let base = strippedCopySuffix(stem, suffix: suffix)
        var index = 1
        while true {
            let stemmed = index == 1 ? "\(base) \(suffix)" : "\(base) \(suffix) \(index)"
            let next = ext.isEmpty ? stemmed : "\(stemmed).\(ext)"
            if !fileExists(folder.appendingPathComponent(next)) { return next }
            index += 1
        }
    }

    /// Splits "Report.pdf" into ("Report", "pdf"). Dot-files and names without a dot have no extension.
    static func split(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    private static func strippedCopySuffix(_ stem: String, suffix: String) -> String {
        if stem.hasSuffix(" \(suffix)") { return String(stem.dropLast(suffix.count + 1)) }
        let parts = stem.split(separator: " ")
        if parts.count >= 3, Int(parts[parts.count - 1]) != nil, parts[parts.count - 2] == Substring(suffix) {
            return parts.dropLast(2).joined(separator: " ")
        }
        return stem
    }
}
