import Foundation
import UniformTypeIdentifiers

/// A uniform type identifier that is safe to report.
///
/// Types declared by Apple (`public.*` and `com.apple.*`) are reported as they are. Any other
/// identifier is declared by a third-party app and would reveal that the app is installed, so it
/// is replaced by its nearest system ancestor. A Sketch document becomes `com.apple.package`
/// or `public.data`, for example. The type system supplies the ancestry, so there is no table
/// of known types to maintain.
nonisolated struct AnalyticsFileType: Equatable, Sendable {
    let identifier: String

    /// Nil when the type is unknown or has no system ancestor.
    init?(_ type: UTType?) {
        guard let type else { return nil }
        if Self.isSystem(type) {
            identifier = type.identifier
            return
        }
        // `supertypes` is the whole ancestry in no order. The nearest ancestor is the one with
        // the most ancestors of its own; the identifier breaks ties so the result is stable.
        let nearest = type.supertypes.filter(Self.isSystem).max { lhs, rhs in
            let (left, right) = (lhs.supertypes.count, rhs.supertypes.count)
            return left == right ? lhs.identifier > rhs.identifier : left < right
        }
        guard let nearest else { return nil }
        identifier = nearest.identifier
    }

    /// Derives the type from the path extension alone. The file is not read and its name is not kept.
    init?(url: URL) {
        self.init(url.hasDirectoryPath && url.pathExtension.isEmpty
            ? .folder : UTType(filenameExtension: url.pathExtension))
    }

    /// The type reported for a folder row.
    static var folder: AnalyticsFileType? { AnalyticsFileType(UTType.folder) }

    /// The type every URL shares, or nil for a mixed or empty selection.
    static func common(of urls: [URL]) -> AnalyticsFileType? {
        guard let first = urls.first.flatMap(AnalyticsFileType.init(url:)) else { return nil }
        return urls.dropFirst().allSatisfy { AnalyticsFileType(url: $0) == first } ? first : nil
    }

    private static func isSystem(_ type: UTType) -> Bool {
        type.identifier.hasPrefix("public.") || type.identifier.hasPrefix("com.apple.")
    }
}
