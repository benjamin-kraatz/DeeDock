import Foundation

/// Rule-based noise: files nobody means to drag anywhere.
///
/// Autosaves and lock files, build products, partial downloads, and temporary items. Noise stays in
/// the history (so a "Show" in the footer can reveal it) but is hidden while **Hide noise** is on.
/// Phase B may add a learned verdict through `FlixItemAnnotation.isNoise`; these rules always apply
/// first because they are certain and free.
nonisolated enum FlixNoiseRules {
    /// Why a path is noise, for tests and for a tooltip.
    nonisolated enum Reason: String, Sendable {
        case autosave, buildProduct, partialDownload, temporary
    }

    /// Suffixes browsers and download tools give a file until it is complete.
    static let partialDownloadExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload",
                                                         "tmp", "aria2"]
    private static let buildExtensions: Set<String> = ["o", "d", "dia", "swiftmodule", "swiftdoc", "swiftsourceinfo",
                                                       "pcm", "dSYM", "xcactivitylog", "obj", "pyc", "class"]
    /// Folder names that only ever hold generated output. Deliberately narrow: "Build" or "dist" can be
    /// a person's own folder, and hiding their files would be worse than showing a stray object file.
    private static let buildFolders: Set<String> = ["DerivedData", "build", ".build", "node_modules",
                                                    "Intermediates.noindex", "__pycache__", ".gradle", "Pods"]
    private static let temporaryFolders = ["/private/var/", "/var/folders/", "/tmp/", "/private/tmp/"]

    /// The reason `path` is noise, or nil for an ordinary file.
    static func reason(forPath path: String) -> Reason? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        if partialDownloadExtensions.contains(ext.lowercased()) { return .partialDownload }
        if isAutosave(name) { return .autosave }
        if temporaryFolders.contains(where: path.hasPrefix) || path.contains("/.TemporaryItems/")
            || path.contains("/.Trash/") || name == ".DS_Store" || name.hasPrefix("Icon\r") {
            return .temporary
        }
        let components = (path as NSString).pathComponents
        if buildExtensions.contains(ext) || components.dropLast().contains(where: buildFolders.contains) {
            return .buildProduct
        }
        return nil
    }

    static func isNoise(path: String?) -> Bool { path.flatMap(reason(forPath:)) != nil }

    /// Office lock files (`~$Report.docx`), LibreOffice locks, editor swap files, and the
    /// `.sb-…` autosave copies AppKit writes beside a document.
    private static func isAutosave(_ name: String) -> Bool {
        if name.hasPrefix("~$") || name.hasPrefix(".~lock.") || name.hasPrefix(".#") { return true }
        if name.contains(".sb-") || name.localizedCaseInsensitiveContains("autosave") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["swp", "swo", "crswap", "lock"].contains(ext) || name.hasSuffix("~")
    }

    /// The final path a partial download becomes once complete, or nil when `path` is not one.
    /// `Report.pdf.crdownload` finishes as `Report.pdf`, so the history can drop the partial entry.
    static func completedPath(ofPartial path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard partialDownloadExtensions.contains(ext), ext != "tmp" else { return nil }
        let base = (path as NSString).deletingPathExtension
        return (base as NSString).pathExtension.isEmpty ? nil : base
    }
}
