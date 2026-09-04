import Foundation
import UniformTypeIdentifiers

/// Classification is completed once per external drag, off the UI actor.
nonisolated enum DockExternalPayload: Sendable {
    case checking
    case selection(pins: [DockPin]?, documents: DocumentResourceAccess?, stageableItems: DocumentResourceAccess?)
    case documents(DocumentResourceAccess)
    case rejected

    var pins: [DockPin] {
        if case .selection(let pins, _, _) = self { return pins ?? [] }
        return []
    }
    var documents: DocumentResourceAccess? {
        switch self {
        case .selection(_, let access, _): return access
        case .documents(let access): return access
        default: return nil
        }
    }
    /// Any complete user-selected batch, whatever it contains: what Trash accepts and what the
    /// Shelf stages. Applications route to pin insertion instead and never reach either tile.
    var stageableItems: DocumentResourceAccess? {
        if case .selection(_, _, let access) = self { return access }
        if case .documents(let access) = self { return access }
        return nil
    }
    var isRejected: Bool { if case .rejected = self { return true }; return false }
    var isChecking: Bool { if case .checking = self { return true }; return false }
    var isReady: Bool { !pins.isEmpty || documents != nil }
    /// Document-only batches need generic application-target feedback. A folder batch defers
    /// to pin insertion unless the pointer is directly over an application.
    var presentsDocumentFallback: Bool { documents != nil && pins.isEmpty }

    /// Rejects incomplete batches before either pin editing or document delivery can occur.
    static func read(_ access: DocumentResourceAccess, excluding ownIdentifier: String,
                     bookmark: (URL) throws -> Data = {
                         try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
                     }) throws -> Self {
        let kinds = try access.urls.map(DockPinImporter.kind)
        let hasApplication = kinds.contains { if case .application = $0 { return true }; return false }
        let allPinnable = kinds.allSatisfy { kind in
            if case .other = kind { return false }
            return true
        }
        if allPinnable {
            let pins = try DockPinImporter.read(access.urls, kinds: kinds, excluding: ownIdentifier, bookmark: bookmark)
            return .selection(pins: pins, documents: hasApplication ? nil : access, stageableItems: access)
        }
        guard !hasApplication else { throw DockDocumentValidationError.unsupportedSelection }
        return .selection(pins: nil, documents: access, stageableItems: access)
    }

    /// Used again immediately before handoff and by the picker. Never traverses folder contents.
    static func validateDocuments(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw CocoaError(.fileReadUnknown) }
        for url in urls {
            try Task.checkCancellation()
            guard url.isFileURL else { throw DockDocumentValidationError.unsupportedSelection }
            if case .application = try DockPinImporter.kind(of: url) {
                throw DockDocumentValidationError.unsupportedSelection
            }
        }
    }
}

/// A complete batch must be document-only before opening; the caller localizes the explanation.
nonisolated enum DockDocumentValidationError: Error {
    case unsupportedSelection
}
