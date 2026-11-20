import Foundation
import UniformTypeIdentifiers

/// What an item is, for the sidebar's Kinds section and for icons.
///
/// Persisted by raw value. ``classify(contentType:isDirectory:isPackage:isScreenshot:)`` is the
/// only place that decides it, so every source agrees.
nonisolated enum FlixItemKind: String, Codable, CaseIterable, Sendable {
    case screenshot
    case image
    case document
    case folder
    case app
    case link
    case other

    /// Decides the kind from what Spotlight or the file system reports.
    ///
    /// - Parameters:
    ///   - contentType: The item's uniform type, when known.
    ///   - isDirectory: A folder. Packages such as apps are not folders.
    ///   - isPackage: A bundle such as an `.app`.
    ///   - isScreenshot: `kMDItemIsScreenCapture` was set. Wins over the image type.
    static func classify(contentType: UTType?, isDirectory: Bool, isPackage: Bool,
                         isScreenshot: Bool) -> FlixItemKind {
        if isScreenshot { return .screenshot }
        if let contentType, contentType.conforms(to: .application) || contentType.conforms(to: .applicationBundle) {
            return .app
        }
        if isDirectory && !isPackage { return .folder }
        guard let contentType else { return .other }
        if contentType.conforms(to: .image) { return .image }
        if contentType.conforms(to: .pdf) || contentType.conforms(to: .text) || contentType.conforms(to: .sourceCode)
            || contentType.conforms(to: .spreadsheet) || contentType.conforms(to: .presentation)
            || contentType.conforms(to: .compositeContent) || contentType.conforms(to: .rtf)
            || contentType.identifier.hasPrefix("com.apple.iwork") || contentType.identifier.hasPrefix("org.openxmlformats")
            || contentType.identifier.hasPrefix("com.microsoft") {
            return .document
        }
        if contentType.conforms(to: .url) || contentType.conforms(to: .internetLocation) { return .link }
        return .other
    }
}
