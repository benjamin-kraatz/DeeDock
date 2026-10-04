import Foundation
import UniformTypeIdentifiers

/// Derives coarse capability tags from an app's declared document types so Robi can tell an image editor
/// from an app that merely shares its App Store category.
///
/// `CFBundleDocumentTypes` is the only local, vendor-declared statement of what an app opens and whether it
/// edits (`Editor`) or only reads (`Viewer`). Proprietary formats and catch-all declarations
/// (`public.data`, `*`) are ignored because they say nothing about the task an app performs.
nonisolated enum LauncherAppCapabilities {
    /// Families checked in order; the first conforming family names a type. Specific families precede the
    /// broad ones they conform to (source code and HTML are also `public.text`).
    private static let families: [(name: String, types: [UTType])] = [
        ("PDF", [.pdf]),
        ("raw photo", [.rawImage]),
        ("vector image", [.svg]),
        ("image", [.image]),
        ("video", [.movie, .video]),
        ("audio", [.audio]),
        ("source code", [.sourceCode, .script]),
        ("web page", [.html]),
        ("spreadsheet", [.spreadsheet, .commaSeparatedText, .tabSeparatedText]),
        ("presentation", [.presentation]),
        ("word-processing document", identifiers("org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
            "org.oasis-open.opendocument.text", "com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages") + [.rtf, .rtfd]),
        ("text", [.text]),
        ("e-book", [.epub]),
        ("archive", [.archive, .diskImage]),
        ("font", [.font]),
        ("3D model", [.threeDContent]),
        ("email", [.emailMessage]),
        ("contact", [.contact]),
        ("calendar", [.calendarEvent]),
    ]

    /// Structured data formats are sidecars and settings for many apps (Photos opens XMP), not a sign of what the app does.
    private static let dataFormats: [UTType] = [.xml, .json, .yaml, .propertyList]

    private static let genericIdentifiers: Set<String> = ["public.item", "public.data", "public.content", "public.folder",
        "public.directory", "public.composite-content", "com.apple.package"]

    /// Returns a compact summary such as `edits image, raw photo; opens PDF`, or an empty string when the app
    /// declares no recognizable document types.
    ///
    /// - Parameter info: The app's unlocalized `Info.plist` dictionary.
    static func summary(info: [String: Any]) -> String {
        guard let documentTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] else { return "" }
        var edits: [String] = [], opens: [String] = []
        for documentType in documentTypes {
            let role = documentType["CFBundleTypeRole"] as? String ?? "Viewer"
            guard role != "None" else { continue }
            for family in familyNames(documentType) {
                if role == "Editor" {
                    if !edits.contains(family) { edits.append(family) }
                } else if !opens.contains(family) {
                    opens.append(family)
                }
            }
        }
        opens.removeAll { edits.contains($0) }
        return [edits.isEmpty ? nil : "edits " + edits.joined(separator: ", "),
                opens.isEmpty ? nil : "opens " + opens.joined(separator: ", ")]
            .compactMap { $0 }.joined(separator: "; ")
    }

    private static func familyNames(_ documentType: [String: Any]) -> [String] {
        var types = (documentType["LSItemContentTypes"] as? [String] ?? [])
            .filter { !genericIdentifiers.contains($0) }.compactMap { UTType($0) }
        // Older bundles declare extensions only. Ignore them when content types exist; both usually describe the same set.
        if types.isEmpty {
            types = (documentType["CFBundleTypeExtensions"] as? [String] ?? [])
                .filter { $0 != "*" }.compactMap { UTType(filenameExtension: $0) }
        }
        var names: [String] = []
        for type in types where !type.isDynamic && !isDataFormat(type) {
            guard let family = families.first(where: { family in family.types.contains { type.conforms(to: $0) } })
            else { continue }
            if !names.contains(family.name) { names.append(family.name) }
        }
        return names
    }

    /// SVG is XML too, but it names a real capability.
    private static func isDataFormat(_ type: UTType) -> Bool {
        !type.conforms(to: .image) && dataFormats.contains { type.conforms(to: $0) }
    }

    private static func identifiers(_ values: String...) -> [UTType] { values.compactMap { UTType($0) } }
}
