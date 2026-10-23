import Darwin
import Foundation

/// An application whose main process has quit while some of its processes keep running.
///
/// macOS 27 keeps such an app's Launch Services record and shows it in the system Dock as
/// "Running in Background". DOKK reads the same record; see `LaunchServicesBackgroundReader`.
nonisolated struct BackgroundApplication: Equatable, Sendable {
    /// The application bundle, standardized so it compares equal to the URL of a pinned tile.
    let bundleURL: URL
    let bundleIdentifier: String?
    /// The name macOS supplies for the app. Never translated.
    let name: String
    /// The remaining processes, each pinned to its start time. Never empty.
    let processes: [BackgroundProcess]
}

/// One process that keeps a background application alive.
///
/// A process ID alone is not an identity: once the process exits, the kernel can reuse its PID
/// for an unrelated process. The start time read at the same moment makes the pair unique, so
/// `isStillRunning` and the stop action can refuse to touch a different process with that PID.
nonisolated struct BackgroundProcess: Hashable, Sendable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64

    /// Reads the identity of a live process owned by the current user.
    ///
    /// Returns `nil` for PID 0, launchd, DOKK itself, processes of another user, and processes
    /// that no longer exist. Only these identities can be watched or signalled.
    init?(pid: pid_t) {
        guard pid > 1, pid != getpid(), let info = Self.bsdInfo(pid), info.pbi_uid == getuid() else { return nil }
        self.pid = pid
        startSeconds = info.pbi_start_tvsec
        startMicroseconds = info.pbi_start_tvusec
    }

    /// Whether this exact process is still alive, rather than a newer process reusing its PID.
    var isStillRunning: Bool { BackgroundProcess(pid: pid) == self }

    /// Sends `signal` only if this exact process is still alive.
    ///
    /// The identity check runs immediately before `kill`, which keeps the window in which the
    /// PID could be reused as small as the system allows. Returns whether the signal was sent.
    @discardableResult
    func send(_ signal: Int32) -> Bool {
        isStillRunning && kill(pid, signal) == 0
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }
}
