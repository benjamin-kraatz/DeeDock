import AppKit
import Darwin

/// Finds the processes that keep a volume busy, using libproc's public volume query.
///
/// Only processes of the current user are visible. Root daemons such as Spotlight can still block
/// an eject without appearing here, which is why the card also handles an empty blocker list.
nonisolated enum VolumeBlockerScanner {
    /// A process that holds files on the volume, before it is mapped to an application.
    struct Process: Equatable, Sendable {
        let pid: pid_t
        let name: String
    }

    /// Lists processes with open files, working directories, or mapped files on the volume.
    /// Walks every process the user can inspect, so run it off the main actor.
    static func processes(onVolumeAt url: URL) -> [Process] {
        let estimate = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard estimate > 0 else { return [] }
        // Room for processes launched between the estimate and the query.
        var pids = [pid_t](repeating: 0, count: Int(estimate) / MemoryLayout<pid_t>.stride + 64)
        let bytes = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return 0 }
            // Event-only descriptors (Finder and Quick Look watching a window) never block an unmount.
            return proc_listpidspath(UInt32(PROC_ALL_PIDS), 0, path,
                                     UInt32(PROC_LISTPIDSPATH_PATH_IS_VOLUME | PROC_LISTPIDSPATH_EXCLUDE_EVTONLY),
                                     &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        }
        guard bytes > 0 else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride)
            .filter { $0 > 0 && $0 != own }
            .map { Process(pid: $0, name: name(of: $0)) }
    }

    /// The BSD parent of `pid`, or nil once the chain reaches launchd or an unreadable process.
    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let parent = pid_t(info.pbi_ppid)
        return parent > 1 ? parent : nil
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "\(pid)"
    }
}

/// Maps busy processes to the applications a person recognizes.
enum VolumeBlockerResolver {
    /// A shell in a Terminal tab is reported as `zsh`; walking up the parent chain finds Terminal,
    /// which is the thing the user can act on. Processes with no application ancestor keep their
    /// own name. Each application appears once, applications first.
    static func blockers(from processes: [VolumeBlockerScanner.Process],
                         parent: (pid_t) -> pid_t? = VolumeBlockerScanner.parent(of:),
                         application: ((pid_t) -> String?)? = nil) -> [VolumeBlocker] {
        let application = application ?? { applicationName(for: $0) }
        var seen = Set<pid_t>()
        var result: [VolumeBlocker] = []
        for process in processes {
            var current: pid_t? = process.pid
            var steps = 0
            var resolved: VolumeBlocker?
            while let pid = current, steps < 8 {
                if let name = application(pid) {
                    resolved = VolumeBlocker(pid: pid, name: name, isApplication: true)
                    break
                }
                current = parent(pid)
                steps += 1
            }
            let blocker = resolved ?? VolumeBlocker(pid: process.pid, name: process.name, isApplication: false)
            // DOKK closes its own stack before ejecting, so it never lists itself as the culprit.
            guard blocker.pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if seen.insert(blocker.pid).inserted { result.append(blocker) }
        }
        return result.filter(\.isApplication) + result.filter { !$0.isApplication }
    }

    /// The name of a regular or accessory application running as `pid`, supplied by macOS.
    static func applicationName(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited else { return nil }
        return app.localizedName
    }
}
