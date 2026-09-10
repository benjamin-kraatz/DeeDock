import Foundation

/// Copies selected files into a folder without replacing anything already there.
///
/// Name collisions receive a numbered alternative (`Report 2.pdf`). Source files stay where they
/// are. A partial batch reports both the copies that landed and the names that failed.
enum LauncherFileCopy {
    struct Outcome: Sendable {
        var copied = 0
        var renamed: [(from: String, to: String)] = []
        var failed: [(name: String, message: String)] = []
    }

    /// Caller hops off the main actor. Grants stay alive for the whole batch, including cancel.
    nonisolated static func perform(_ sources: DocumentResourceAccess, to destination: URL,
                                    destinationAccess: LauncherFileDestinationAccess) -> Outcome {
        defer { withExtendedLifetime((sources, destinationAccess)) {} }
        var outcome = Outcome()
        let manager = FileManager.default
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        var used = Set<String>()
        for source in sources.urls {
            if Task.isCancelled {
                outcome.failed.append((source.lastPathComponent, String(localized: .launcherFileCancelled)))
                continue
            }
            let canonical = source.resolvingSymlinksInPath().standardizedFileURL
            let originalName = source.lastPathComponent
            if target == canonical || target.path.hasPrefix(canonical.path + "/") {
                outcome.failed.append((originalName, String(localized: .launcherFileCopyIntoSelf)))
                continue
            }
            let name = uniqueName(originalName, used: &used, destination: target)
            do {
                try manager.copyItem(at: source, to: target.appendingPathComponent(name))
                outcome.copied += 1
                if name != originalName { outcome.renamed.append((originalName, name)) }
            } catch {
                outcome.failed.append((originalName, error.localizedDescription))
            }
        }
        return outcome
    }

    /// Prefers the original name. Existing destination entries and earlier copies in this batch
    /// keep their names; this never overwrites.
    nonisolated static func uniqueName(_ fileName: String, used: inout Set<String>, destination: URL) -> String {
        let ns = fileName as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var candidate = fileName
        var index = 2
        while used.contains(candidate)
                || FileManager.default.fileExists(atPath: destination.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            index += 1
        }
        used.insert(candidate)
        return candidate
    }
}
