import AppKit
import UniformTypeIdentifiers

/// Declared application support for a batch, queried through public Workspace APIs.
///
/// A listed handler is not a guarantee that every file will open. Heterogeneous batches stay
/// visible: an app that accepts only some files is marked mixed instead of dropping the rest.
nonisolated enum LauncherFileCompatibility {
    struct Snapshot: Sendable {
        /// Bundle identifiers and path identities that declare support for each URL.
        let handlers: [URL: Set<String>]
    }

    /// Reads registered handlers without opening files or ranking by content.
    static func snapshot(urls: [URL]) -> Snapshot {
        var handlers: [URL: Set<String>] = [:]
        for url in urls {
            var identities = Set<String>()
            for application in NSWorkspace.shared.urlsForApplications(toOpen: url) {
                let standardized = application.standardizedFileURL
                identities.insert(standardized.path)
                if let identifier = Bundle(url: standardized)?.bundleIdentifier {
                    identities.insert(identifier)
                }
            }
            if let type = contentType(for: url) {
                for application in NSWorkspace.shared.urlsForApplications(toOpen: type) {
                    let standardized = application.standardizedFileURL
                    identities.insert(standardized.path)
                    if let identifier = Bundle(url: standardized)?.bundleIdentifier {
                        identities.insert(identifier)
                    }
                }
            }
            handlers[url.standardizedFileURL] = identities
        }
        return Snapshot(handlers: handlers)
    }

    static func contentType(for url: URL) -> UTType? {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
            return .folder
        }
        return UTType(filenameExtension: url.pathExtension)
    }

    /// How many of the available files this application identity declares support for.
    static func support(for application: ApplicationReference, urls: [URL], in snapshot: Snapshot) -> (supported: [URL], unsupported: [URL]) {
        let identities = Set([application.id, application.bundleIdentifier, application.url.standardizedFileURL.path].compactMap { $0 })
        var supported: [URL] = []
        var unsupported: [URL] = []
        for url in urls {
            let handlers = snapshot.handlers[url.standardizedFileURL] ?? []
            if identities.contains(where: handlers.contains) {
                supported.append(url)
            } else {
                unsupported.append(url)
            }
        }
        return (supported, unsupported)
    }
}

/// Declared support for one action and the current batch. Shortcuts stay unknown.
nonisolated enum LauncherFileSupport: String, Sendable, Equatable {
    case all
    case mixed
    case none
    case unknown
}
