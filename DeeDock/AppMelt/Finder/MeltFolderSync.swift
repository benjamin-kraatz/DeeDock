import Foundation
import CryptoKit

nonisolated struct MeltSyncEntry: Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case add, replace, directory, blocked }
    let path: String
    let kind: Kind
    let sourceHash: String?
    let destinationHash: String?
    var id: String { path }
}

nonisolated struct MeltSyncPlan: Sendable {
    let source: URL
    let destination: URL
    let entries: [MeltSyncEntry]
    let sourceIdentity: String
    let destinationIdentity: String
}

/// One-shot merge. Destination-only items are never removed. Symlinks and type conflicts
/// are listed but never followed or overwritten. All file content work stays off MainActor.
actor MeltFolderSync {
    private let files = FileManager.default

    func preview(source: URL, destination: URL) throws -> MeltSyncPlan {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !contains(source, destination), !contains(destination, source) else { throw MeltFinderError.overlapping }
        guard try kind(source) == .typeDirectory, try kind(destination) == .typeDirectory else { throw MeltFinderError.unsupported }
        let sourceIdentity = try identity(source)
        let destinationIdentity = try identity(destination)
        var entries: [MeltSyncEntry] = []
        try scan(source, destination, relative: "", entries: &entries)
        guard try identity(source) == sourceIdentity, try identity(destination) == destinationIdentity else {
            throw MeltFinderError.changed
        }
        return MeltSyncPlan(source: source, destination: destination, entries: entries,
            sourceIdentity: sourceIdentity, destinationIdentity: destinationIdentity)
    }

    private func scan(_ source: URL, _ destination: URL, relative: String, entries: inout [MeltSyncEntry]) throws {
        for child in try files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
            let target = destination.appendingPathComponent(child.lastPathComponent)
            let sourceKind = try kind(child)
            if sourceKind == .typeDirectory, try child.resourceValues(forKeys: [.isPackageKey]).isPackage == true {
                entries.append(MeltSyncEntry(path: path, kind: .blocked, sourceHash: nil, destinationHash: nil))
                continue
            }
            let targetKind = try optionalKind(target)
            if targetKind == .typeDirectory, try target.resourceValues(forKeys: [.isPackageKey]).isPackage == true {
                entries.append(MeltSyncEntry(path: path, kind: .blocked, sourceHash: nil, destinationHash: nil))
                continue
            }
            if sourceKind == .typeDirectory, targetKind == nil || targetKind == .typeDirectory {
                if targetKind == nil { entries.append(MeltSyncEntry(path: path, kind: .directory, sourceHash: nil, destinationHash: nil)) }
                try scan(child, target, relative: path, entries: &entries)
            } else if sourceKind == .typeRegular, targetKind == nil || targetKind == .typeRegular {
                let sourceHash = try hash(child)
                let targetHash = targetKind == nil ? nil : try hash(target)
                if sourceHash != targetHash {
                    entries.append(MeltSyncEntry(path: path, kind: targetHash == nil ? .add : .replace,
                        sourceHash: sourceHash, destinationHash: targetHash))
                }
            } else {
                entries.append(MeltSyncEntry(path: path, kind: .blocked, sourceHash: nil, destinationHash: nil))
            }
        }
    }

    /// Returns only after the requested merge finishes. A thrown error may follow completed
    /// copies; the UI must retain that distinction and require a fresh preview before retrying.
    func apply(_ plan: MeltSyncPlan, replacing: Bool, progress: @Sendable (Int) async -> Void) async throws {
        var completed = 0
        for entry in plan.entries {
            try Task.checkCancellation()
            guard try identity(plan.source) == plan.sourceIdentity,
                  try identity(plan.destination) == plan.destinationIdentity else { throw MeltFinderError.changed }
            if entry.kind == .blocked || (entry.kind == .replace && !replacing) { continue }
            let source = plan.source.appendingPathComponent(entry.path)
            let destination = plan.destination.appendingPathComponent(entry.path)
            try validatePath(source, root: plan.source)
            try validatePath(destination, root: plan.destination)
            if entry.kind == .directory {
                guard try kind(source) == .typeDirectory else { throw MeltFinderError.changed }
                if let existing = try optionalKind(destination) {
                    guard existing == .typeDirectory else { throw MeltFinderError.changed }
                } else { try files.createDirectory(at: destination, withIntermediateDirectories: false) }
            } else {
                try copy(entry, source: source, destination: destination, plan: plan)
            }
            completed += 1
            await progress(completed)
        }
    }

    private func copy(_ entry: MeltSyncEntry, source: URL, destination: URL, plan: MeltSyncPlan) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: [], error: &coordinationError) { source, destination in
            do {
                try Task.checkCancellation()
                try validatePath(source, root: plan.source)
                try validatePath(destination, root: plan.destination)
                guard source.standardizedFileURL == plan.source.appendingPathComponent(entry.path).standardizedFileURL,
                      destination.standardizedFileURL == plan.destination.appendingPathComponent(entry.path).standardizedFileURL,
                      try identity(plan.source) == plan.sourceIdentity,
                      try identity(plan.destination) == plan.destinationIdentity else { throw MeltFinderError.changed }
                guard try kind(source) == .typeRegular, try hash(source) == entry.sourceHash else { throw MeltFinderError.changed }
                let destinationKind = try optionalKind(destination)
                if let expected = entry.destinationHash {
                    guard destinationKind == .typeRegular, try hash(destination) == expected else { throw MeltFinderError.changed }
                } else if destinationKind != nil { throw MeltFinderError.changed }
                // Copy to a sibling first, leaving the existing destination untouched on failure.
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ddock-sync-" + UUID().uuidString)
                defer { try? files.removeItem(at: temporary) }
                try files.copyItem(at: source, to: temporary)
                guard try hash(temporary) == entry.sourceHash else { throw MeltFinderError.changed }
                try Task.checkCancellation()
                // Staging may take seconds or minutes. Recheck the destination after that
                // work so an edit made during the copy is not replaced by an older preview.
                try validatePath(source, root: plan.source)
                try validatePath(destination, root: plan.destination)
                guard try identity(plan.source) == plan.sourceIdentity,
                      try identity(plan.destination) == plan.destinationIdentity else { throw MeltFinderError.changed }
                if let expected = entry.destinationHash {
                    guard try optionalKind(destination) == .typeRegular,
                          try hash(destination) == expected else { throw MeltFinderError.changed }
                } else if try optionalKind(destination) != nil { throw MeltFinderError.changed }
                try Task.checkCancellation()
                if entry.destinationHash != nil {
                    _ = try files.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try files.moveItem(at: temporary, to: destination)
                }
            } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
    }

    private func validatePath(_ url: URL, root: URL) throws {
        guard contains(root, url), url != root,
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else { throw MeltFinderError.changed }
    }
    private func contains(_ parent: URL, _ child: URL) -> Bool {
        parent == child || child.path.hasPrefix(parent.path.hasSuffix("/") ? parent.path : parent.path + "/")
    }
    private func identity(_ url: URL) throws -> String {
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { throw MeltFinderError.unavailable }
        return "\(device):\(inode)"
    }
    private func kind(_ url: URL) throws -> FileAttributeType? {
        try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    }
    private func optionalKind(_ url: URL) throws -> FileAttributeType? {
        do { return try kind(url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
    }
    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
