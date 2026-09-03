import Foundation
import UniformTypeIdentifiers

/// Classification is completed once per external drag, off the UI actor.
nonisolated enum DockExternalPayload: Sendable {
    case checking
    case applications([ApplicationReference])
    case documents(DocumentResourceAccess)
    case rejected

    var applications: [ApplicationReference] {
        if case .applications(let apps) = self { return apps }
        return []
    }
    var documents: DocumentResourceAccess? {
        if case .documents(let access) = self { return access }
        return nil
    }
    var isRejected: Bool { if case .rejected = self { return true }; return false }
    var isReady: Bool { !applications.isEmpty || documents != nil }

    /// Rejects incomplete batches before either pin editing or document delivery can occur.
    static func read(_ access: DocumentResourceAccess, excluding ownIdentifier: String,
                     bookmark: (URL) throws -> Data = {
                         try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
                     }) throws -> Self {
        let applicationFlags = try classify(access.urls)
        if applicationFlags.allSatisfy({ $0 }) {
            let apps = try DockApplicationImporter.read(access.urls, excluding: ownIdentifier, bookmark: bookmark)
            var identities = Set<String>()
            return .applications(apps.filter { identities.insert($0.id).inserted })
        }
        guard !applicationFlags.contains(true) else { throw DockDocumentValidationError.unsupportedSelection }
        return .documents(access)
    }

    /// Used again immediately before handoff and by the picker. Never traverses folder contents.
    static func validateDocuments(_ urls: [URL]) throws {
        guard try !classify(urls).contains(true) else { throw DockDocumentValidationError.unsupportedSelection }
    }

    private static func classify(_ urls: [URL]) throws -> [Bool] {
        guard !urls.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return try urls.map { url in
            try Task.checkCancellation()
            guard url.isFileURL else { throw DockDocumentValidationError.unsupportedSelection }
            var probe = url
            probe.removeAllCachedResourceValues()
            let values = try probe.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isRegularFileKey, .isReadableKey])
            guard values.isReadable != false, values.isDirectory == true || values.isRegularFile == true else {
                throw CocoaError(.fileReadNoPermission)
            }
            // Broken or unregistered .app bundles must never become document payloads.
            return values.contentType?.conforms(to: .applicationBundle) == true || url.pathExtension.lowercased() == "app"
        }
    }
}

/// A complete batch must be document-only before opening; the caller localizes the explanation.
nonisolated enum DockDocumentValidationError: Error {
    case unsupportedSelection
}
