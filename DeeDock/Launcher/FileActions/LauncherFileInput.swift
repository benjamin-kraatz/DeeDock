import Foundation
import UniformTypeIdentifiers

/// One selected file or folder in the order the user supplied it.
///
/// Availability is existence plus a live access grant. Type identifiers come from the
/// filename extension or directory flag, never from reading file contents.
nonisolated struct LauncherFileInput: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let isAvailable: Bool
    let isDirectory: Bool
    /// Uniform type identifier when the extension or directory kind is known.
    let typeIdentifier: String?

    init(id: UUID = UUID(), url: URL, name: String? = nil, isAvailable: Bool, isDirectory: Bool? = nil) {
        self.id = id
        self.url = url.standardizedFileURL
        self.name = name ?? FileManager.default.displayName(atPath: self.url.path)
        self.isAvailable = isAvailable
        if let isDirectory {
            self.isDirectory = isDirectory
        } else {
            var directory: ObjCBool = false
            self.isDirectory = FileManager.default.fileExists(atPath: self.url.path, isDirectory: &directory)
                && directory.boolValue
        }
        if self.isDirectory {
            typeIdentifier = UTType.folder.identifier
        } else if let type = UTType(filenameExtension: self.url.pathExtension) {
            typeIdentifier = type.identifier
        } else {
            typeIdentifier = nil
        }
    }
}

/// How the current batch entered the Launcher. Ownership still lives on `DocumentResourceAccess`.
nonisolated enum LauncherFileSource: String, Sendable, Equatable {
    case shelf
    case drop
    case picker
}

/// A presentation-scoped batch. The access object is the live grant; it is never serialized.
@MainActor
final class LauncherFileContext {
    /// Rejects callbacks from a replaced or cleared batch.
    let generation: UUID
    let source: LauncherFileSource
    /// Temporary user-selected access, including retained Shelf or drag-lease owners.
    let access: DocumentResourceAccess?
    /// Every supplied item, including unavailable ones, in selection order.
    let inputs: [LauncherFileInput]

    static let capacity = 50

    init(generation: UUID = UUID(), source: LauncherFileSource, access: DocumentResourceAccess?,
         inputs: [LauncherFileInput]) {
        self.generation = generation
        self.source = source
        self.access = access
        self.inputs = Array(inputs.prefix(Self.capacity))
    }

    var availableInputs: [LauncherFileInput] { inputs.filter(\.isAvailable) }
    var unavailableInputs: [LauncherFileInput] { inputs.filter { !$0.isAvailable } }
    var availableURLs: [URL] { availableInputs.map(\.url) }
}

/// Values passed across the Shelf, drop, and picker boundaries without copying URLs into a new lease.
struct LauncherFileAdoption {
    let source: LauncherFileSource
    let access: DocumentResourceAccess?
    let inputs: [LauncherFileInput]
    let overflowed: Bool

    /// Builds an adoption from already-owned access. Callers must not wrap drag-lease URLs again.
    static func owned(_ access: DocumentResourceAccess, source: LauncherFileSource,
                      extras: [LauncherFileInput] = []) -> Self {
        var seen = Set(access.urls.map(\.standardizedFileURL))
        var inputs = access.urls.map { url in
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            return LauncherFileInput(url: url, isAvailable: exists, isDirectory: exists && directory.boolValue)
        }
        for extra in extras where seen.insert(extra.url.standardizedFileURL).inserted {
            inputs.append(extra)
        }
        let overflowed = inputs.count > LauncherFileContext.capacity
        return LauncherFileAdoption(source: source, access: access,
                                    inputs: Array(inputs.prefix(LauncherFileContext.capacity)),
                                    overflowed: overflowed)
    }
}
