import Foundation
import UniformTypeIdentifiers

/// The document types an app declares it opens or edits, for telling which files fit its picker.
///
/// The picker itself cannot say: `AXEnabled` is true for every row, greyed or not, so the types the
/// picker accepts are not readable through Accessibility. The app's bundle is the next best source:
/// `CFBundleDocumentTypes` (`LSItemContentTypes`, or `CFBundleTypeExtensions` in older bundles)
/// with the role Viewer or Editor, and the app's own `UTImportedTypeDeclarations` and
/// `UTExportedTypeDeclarations` for types macOS may not know by identifier. A catch-all declaration
/// (`public.data`, `public.item`, `public.content`, `*`, `****`), or no declaration at all, means
/// any file fits: Flix Pick then does not filter by type.
///
/// Pure value type; ``load(bundleURL:)`` reads the bundle's `Info.plist` and must run off the main
/// actor.
nonisolated struct FlixPickDocumentTypes: Equatable, Sendable {
    /// Declared types, resolved once.
    var types: [UTType] = []
    /// Lowercased extensions declared directly or through the app's type declarations.
    var extensions: Set<String> = []
    var acceptsFolders = false
    var acceptsAnything = true

    /// Every file fits; folders do not.
    static let anything = FlixPickDocumentTypes()

    private static let catchAll: Set<String> = ["public.data", "public.item", "public.content", "public.composite-content"]
    private static let folders: Set<String> = ["public.folder", "public.directory"]

    init() {}

    /// Parses an app's `Info.plist` dictionary.
    ///
    /// - Parameter editorsOnly: Only types the app edits (role Editor), for Save pickers; without
    ///   any, falls back to every role.
    init(info: [String: Any], editorsOnly: Bool = false) {
        let documentTypes = (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).filter {
            ($0["CFBundleTypeRole"] as? String ?? "Viewer") != "None"
        }
        let editors = documentTypes.filter { ($0["CFBundleTypeRole"] as? String) == "Editor" }
        let chosen = editorsOnly && !editors.isEmpty ? editors : documentTypes
        guard !chosen.isEmpty else { return }
        acceptsAnything = false
        let declared = Self.declarations(info)
        var identifiers = Set<String>()
        for documentType in chosen {
            for identifier in documentType["LSItemContentTypes"] as? [String] ?? [] {
                if Self.catchAll.contains(identifier) { acceptsAnything = true }
                if Self.folders.contains(identifier) { acceptsFolders = true; continue }
                identifiers.insert(identifier)
                if let declaration = declared[identifier] {
                    extensions.formUnion(declaration.extensions)
                    identifiers.formUnion(declaration.conformsTo.filter { !Self.catchAll.contains($0) })
                }
            }
            for ext in documentType["CFBundleTypeExtensions"] as? [String] ?? [] {
                if ext == "*" { acceptsAnything = true } else { extensions.insert(ext.lowercased()) }
            }
            for code in documentType["CFBundleTypeOSTypes"] as? [String] ?? [] {
                if code == "****" { acceptsAnything = true }
                if code == "fold" { acceptsFolders = true }
            }
        }
        types = identifiers.sorted().compactMap { UTType($0) }.filter { !$0.isDynamic }
    }

    /// The app's types for its Open picker and its Save picker, read from its bundle. Off the main
    /// actor: it reads `Info.plist` from disk. An unreadable bundle fits anything.
    static func load(bundleURL: URL) -> (open: FlixPickDocumentTypes, save: FlixPickDocumentTypes) {
        guard let info = Bundle(url: bundleURL)?.infoDictionary else { return (.anything, .anything) }
        return (FlixPickDocumentTypes(info: info), FlixPickDocumentTypes(info: info, editorsOnly: true))
    }

    /// Whether a file or folder fits.
    func fits(type: UTType?, pathExtension: String, isFolder: Bool) -> Bool {
        if isFolder { return acceptsFolders }
        if acceptsAnything { return true }
        if !pathExtension.isEmpty, extensions.contains(pathExtension.lowercased()) { return true }
        let resolved = type ?? (pathExtension.isEmpty ? nil : UTType(filenameExtension: pathExtension))
        guard let resolved else { return false }
        return types.contains { resolved.conforms(to: $0) }
    }

    /// `fits(type:pathExtension:isFolder:)` for a Flix item.
    func fits(_ item: FlixItem) -> Bool {
        let ext = ((item.path ?? "") as NSString).pathExtension
        return fits(type: item.contentType, pathExtension: ext, isFolder: item.kind == .folder)
    }

    /// The app's own type declarations, by identifier.
    private static func declarations(_ info: [String: Any]) -> [String: (extensions: Set<String>, conformsTo: [String])] {
        let all = (info["UTImportedTypeDeclarations"] as? [[String: Any]] ?? [])
            + (info["UTExportedTypeDeclarations"] as? [[String: Any]] ?? [])
        var result: [String: (extensions: Set<String>, conformsTo: [String])] = [:]
        for declaration in all {
            guard let identifier = declaration["UTTypeIdentifier"] as? String else { continue }
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            let extensions = strings(tags?["public.filename-extension"]).map { $0.lowercased() }
            result[identifier] = (Set(extensions), strings(declaration["UTTypeConformsTo"]))
        }
        return result
    }

    /// A plist value that is one string or a list of them.
    private static func strings(_ value: Any?) -> [String] {
        if let one = value as? String { return [one] }
        return value as? [String] ?? []
    }
}
