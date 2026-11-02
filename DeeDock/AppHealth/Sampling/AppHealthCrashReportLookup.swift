import Foundation

/// Answers whether macOS wrote a crash report for an app around its termination. Tests pass a fake.
nonisolated protocol AppHealthCrashReportLooking: Sendable {
    /// - Parameters:
    ///   - executableName: The app's executable file name. Used for matching only; never stored.
    ///   - since: The earliest modification date that counts.
    func hasReport(executableName: String, since: Date) async -> Bool
}

/// Lists `~/Library/Logs/DiagnosticReports` for an `.ips` file named after the executable.
///
/// Only the answer is kept. The directory listing runs on a utility queue, never on the main actor.
nonisolated final class AppHealthCrashReportLookup: AppHealthCrashReportLooking {
    private let directory: URL
    private let queue = DispatchQueue(label: "de.benjaminkraatz.DeeDock.AppHealth.crashReports", qos: .utility)

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func hasReport(executableName: String, since: Date) async -> Bool {
        let directory = directory
        return await withCheckedContinuation { continuation in
            queue.async {
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
                let found = entries.contains { url in
                    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    return Self.matches(fileName: url.lastPathComponent, modified: modified,
                                        executableName: executableName, since: since)
                }
                continuation.resume(returning: found)
            }
        }
    }

    /// A report counts when it is an `.ips` file, its name starts with the executable name and a hyphen
    /// (`Safari-2026-11-02-101500.ips`), and it was modified at or after `since`.
    static func matches(fileName: String, modified: Date?, executableName: String, since: Date) -> Bool {
        guard !executableName.isEmpty, fileName.hasSuffix(".ips"), fileName.hasPrefix(executableName + "-"),
              let modified else { return false }
        return modified >= since
    }
}
