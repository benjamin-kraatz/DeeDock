import AppKit
import Darwin

/// Finds the processes that keep a volume busy, using libproc's public volume query.
///
/// The volume query only sees processes of the current user. A system process, such as the one
/// that keeps Preview's document versions, can still block an eject; macOS then names it only as
/// the unmount's dissenter, and `describe` turns that bare process ID into a name and a path.
nonisolated enum VolumeBlockerScanner {
    /// A process that holds files on the volume, before it is mapped to an application.
    struct Process: Equatable, Sendable {
        let pid: pid_t
        let name: String
        /// The program file, when macOS reports it.
        var path: String? = nil
        /// True when the process runs as another user, typically root, and so belongs to macOS.
        var isSystem = false
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
            .map(describe)
    }

    /// Names any process, including root-owned ones that libproc refuses to inspect. The kernel
    /// process table answers for every process; libproc then adds the full program path, whose file
    /// name is not cut off at 16 characters the way the table's command name is.
    static func describe(_ pid: pid_t) -> Process {
        let entry = kernelEntry(pid)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        let command = entry.map { entry in
            withUnsafeBytes(of: entry.kp_proc.p_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? command ?? "\(pid)"
        let isSystem = entry.map { $0.kp_eproc.e_ucred.cr_uid != getuid() } ?? true
        return Process(pid: pid, name: name, path: path, isSystem: isSystem)
    }

    /// The BSD parent of `pid`, or nil once the chain reaches launchd or an unknown process.
    static func parent(of pid: pid_t) -> pid_t? {
        guard let parent = kernelEntry(pid)?.kp_eproc.e_ppid, parent > 1 else { return nil }
        return parent
    }

    /// The kernel's process-table entry, readable for every process without extra privileges.
    private static func kernelEntry(_ pid: pid_t) -> kinfo_proc? {
        var entry = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&query, UInt32(query.count), &entry, &size, nil, 0) == 0, size > 0 else { return nil }
        return entry
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
            let blocker = resolved ?? VolumeBlocker(pid: process.pid, name: process.name, isApplication: false,
                                                    executablePath: process.path, isSystem: process.isSystem)
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
