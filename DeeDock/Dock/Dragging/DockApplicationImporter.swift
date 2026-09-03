import Foundation
import UniformTypeIdentifiers

/// Validates complete Finder batches off the UI actor, without executing bundle code or launching apps.
enum DockApplicationImporter {
    nonisolated static func read(_ urls: [URL], excluding ownIdentifier: String,
                                bookmark: (URL) throws -> Data = {
                                    try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                        includingResourceValuesForKeys: nil, relativeTo: nil)
                                }) throws -> [ApplicationReference] {
        guard !urls.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return try urls.map { input in
            try Task.checkCancellation()
            guard input.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
            let scoped = input.startAccessingSecurityScopedResource()
            defer { if scoped { input.stopAccessingSecurityScopedResource() } }
            let url = input.standardizedFileURL.resolvingSymlinksInPath()
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isReadableKey, .localizedNameKey])
            guard values.contentType?.conforms(to: .applicationBundle) == true,
                  values.isDirectory == true, values.isReadable != false,
                  let bundle = Bundle(url: url), bundle.bundleIdentifier != ownIdentifier,
                  bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let bookmarkData = try bookmark(url)
            let name = values.localizedName ?? url.lastPathComponent
            return ApplicationReference(bundleIdentifier: bundle.bundleIdentifier, url: url,
                                        name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                                        bookmarkData: bookmarkData)
        }
    }
}
