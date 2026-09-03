import Foundation
import UniformTypeIdentifiers

/// Builds an ordered pin batch from user-granted application bundles and ordinary folders.
nonisolated enum DockPinImporter {
    enum Kind: Equatable, Sendable { case application, folder, other }

    static func kind(of url: URL) throws -> Kind {
        var probe = url
        probe.removeAllCachedResourceValues()
        let values = try probe.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey,
                                                         .isAliasFileKey, .isSymbolicLinkKey, .isReadableKey])
        guard values.isReadable != false, values.isDirectory == true || values.contentType != nil else {
            throw CocoaError(.fileReadNoPermission)
        }
        if values.contentType?.conforms(to: .applicationBundle) == true || url.pathExtension.lowercased() == "app" {
            return .application
        }
        if values.isDirectory == true, values.isPackage != true, values.isAliasFile != true,
           values.isSymbolicLink != true { return .folder }
        return .other
    }

    static func read(_ urls: [URL], kinds: [Kind], excluding ownIdentifier: String,
                     bookmark: (URL) throws -> Data = {
                         try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
                     }) throws -> [DockPin] {
        var result: [DockPin] = []
        for (url, kind) in zip(urls, kinds) {
            try Task.checkCancellation()
            switch kind {
            case .application:
                result.append(contentsOf: try DockApplicationImporter.read([url], excluding: ownIdentifier, bookmark: bookmark)
                    .map(DockPin.application))
            case .folder:
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL
                result.append(.folder(FolderReference(url: canonical,
                    name: FileManager.default.displayName(atPath: canonical.path),
                    bookmarkData: try bookmark(canonical))))
            case .other:
                throw DockDocumentValidationError.unsupportedSelection
            }
        }
        return uniqueFolders(DockPinEditing.unique(result))
    }

    private static func uniqueFolders(_ pins: [DockPin]) -> [DockPin] {
        var folderURLs = Set<URL>()
        return pins.filter { pin in
            guard let folder = pin.folder else { return true }
            return folderURLs.insert(folder.url.standardizedFileURL).inserted
        }
    }
}
