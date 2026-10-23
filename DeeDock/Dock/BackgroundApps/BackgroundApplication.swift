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
    /// The remaining processes, each pinned to one process instance. Never empty.
    let processes: [BackgroundProcess]
}

/// One process instance that keeps a background application alive.
///
/// A process ID alone is not an identity: once a process exits, the kernel can give its PID to
/// an unrelated process. The kernel's audit token for the process carries a per-instance version
/// as well, and `proc_signal_with_audittoken` delivers a signal only while that exact instance
/// is alive. The kernel performs that check atomically with the delivery, so no window remains
/// between checking the identity and signalling.
nonisolated struct BackgroundProcess: Hashable, Sendable {
    let pid: pid_t
    /// Compared and hashed as a whole; DOKK never reads its fields, which `libbsm` reserves.
    private let token: audit_token_t

    /// Captures the identity of a live process owned by the current user.
    ///
    /// Returns `nil` for PID 0, launchd, DOKK itself, processes of another user, and processes
    /// that no longer exist. Only these identities can be watched or signalled.
    init?(pid: pid_t) {
        guard pid > 1, pid != getpid(), let info = Self.bsdInfo(pid), info.pbi_uid == getuid(),
              let token = Self.auditToken(for: pid) else { return nil }
        self.init(pid: pid, token: token)
    }

    /// Wraps a token captured elsewhere. Tests use it to build an identity that is no longer alive.
    init(pid: pid_t, token: audit_token_t) {
        self.pid = pid
        self.token = token
    }

    /// Whether this exact process instance is still alive, rather than a newer one with its PID.
    var isStillRunning: Bool { BackgroundProcess(pid: pid) == self }

    /// Sends `signal` to this exact process instance. Returns whether the kernel delivered it.
    ///
    /// The kernel refuses the signal with `ESRCH` once the instance has exited, even if its PID
    /// already belongs to another process, and applies the same permission rules as `kill`.
    @discardableResult
    func send(_ signal: Int32) -> Bool {
        var token = token
        return proc_signal_with_audittoken(&token, signal) == 0
    }

    /// The kernel's audit token for `pid`, read through its task name port.
    ///
    /// A name port grants no control over the task. Reading it needs no entitlement for a
    /// process of the same user, which is the only kind DOKK signals.
    static func auditToken(for pid: pid_t) -> audit_token_t? {
        var name: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &name) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, name) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(name, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? token : nil
    }

    static func == (lhs: BackgroundProcess, rhs: BackgroundProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.words == rhs.words
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(words)
    }

    private var words: [UInt32] {
        let value = token.val
        return [value.0, value.1, value.2, value.3, value.4, value.5, value.6, value.7]
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }
}
