import Foundation

/// Reads folders for onboarding and Settings: whether Lookout may read one, and what the first pass over it costs.
/// The live one touches the disk off the main actor; previews and tests use stand-ins that never do.
nonisolated protocol LookoutFolderInspecting: Sendable {
    /// Lists the folder's contents to find out whether it may be read. For a protected folder (Desktop, Documents,
    /// Downloads, other volumes) this is what makes macOS show its Files and Folders prompt the first time, and the
    /// call waits for the person's answer; after that macOS answers at once without asking again.
    func access(_ path: String) async -> LookoutFolderAccess

    /// The first pass's estimate from metadata alone (`Crawler` and `Estimator`), or nil when it can't be read.
    /// Callers only estimate folders that read without a prompt or are allowed already.
    func estimate(_ path: String) async -> LookoutFolderEstimate?
}

/// The real inspector.
nonisolated struct LookoutLiveFolderInspector: LookoutFolderInspecting {
    func access(_ path: String) async -> LookoutFolderAccess {
        await Self.readAccess(path)
    }

    func estimate(_ path: String) async -> LookoutFolderEstimate? {
        await Self.readEstimate(path)
    }

    /// The read blocks while macOS shows its prompt, which can take as long as the person likes, so it runs on a
    /// dispatch queue rather than holding one of Swift's few cooperative threads.
    private static func readAccess(_ path: String) async -> LookoutFolderAccess {
        await onWorkQueue {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return .missing
            }
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return .allowed
            } catch {
                return .denied
            }
        }
    }

    /// A crawl of a big folder takes a second or more of disk reads; it runs on a dispatch queue too.
    private static func readEstimate(_ path: String) async -> LookoutFolderEstimate? {
        await onWorkQueue {
            let options = IndexOptions()
            let report = Crawler.crawl([URL(fileURLWithPath: path, isDirectory: true)], options: options,
                                       readsLastUsed: false)
            let estimate = Estimator.estimate(report.candidates, options: options)
            return LookoutFolderEstimate(files: estimate.fileCount, seconds: estimate.seconds, bytes: estimate.bytes)
        }
    }

    private static func onWorkQueue<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }
}

/// An inspector for previews and tests: fixed answers by path (allowed and a small estimate otherwise), after an
/// optional delay. It never touches the disk.
nonisolated struct LookoutStubFolderInspector: LookoutFolderInspecting {
    var accessByPath: [String: LookoutFolderAccess] = [:]
    var estimates: [String: LookoutFolderEstimate] = [:]
    var delay: Duration = .zero

    func access(_ path: String) async -> LookoutFolderAccess {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return accessByPath[path] ?? .allowed
    }

    func estimate(_ path: String) async -> LookoutFolderEstimate? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return estimates[path] ?? LookoutFolderEstimate(files: 120, seconds: 40, bytes: 4_000_000)
    }
}
