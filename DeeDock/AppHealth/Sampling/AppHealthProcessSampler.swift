import Darwin
import Foundation

/// The result of one sampler pass.
nonisolated struct AppHealthSamplerResult: Sendable {
    /// Seconds since the previous pass, or nil on a baseline pass, whose deltas mean nothing.
    let interval: Double?
    /// Per bundle identifier. An app with no attributable process this pass is absent.
    let usage: [String: AppHealthAppUsage]
    /// Process identifiers attributed to each bundle this pass, main process and helpers.
    /// Empty when a caller does not need them.
    var pids: [String: Set<pid_t>] = [:]
    /// Thread CPU time the pass spent, in milliseconds.
    let costMilliseconds: Double
}

/// Reads per-app resource use. The live implementation is `AppHealthProcessSampler`; tests pass a fake.
nonisolated protocol AppHealthSampling: Actor {
    /// Forgets every process's previous counters, so the next pass only re-establishes baselines.
    func resetBaselines()
    /// Reads every same-user process once and attributes its use over the interval to `apps`.
    func sample(_ apps: [AppHealthWatchedApp]) -> AppHealthSamplerResult
}

/// Reads libproc for every same-user process, attributes each process to a watched app, and turns cumulative
/// counters into per-tick deltas.
///
/// All libproc work happens on this actor, never on the main actor. `proc_pid_rusage` and `proc_pidinfo` succeed
/// only for processes owned by the current user, so other users' processes are skipped up front. Executable paths
/// are read at most once per process lifetime, only for processes whose parent chain does not reach an app, and
/// never leave this actor.
actor AppHealthProcessSampler: AppHealthSampling {
    /// One process instance for delta bookkeeping: a pid is reused, its start time is not.
    private struct ProcessKey: Hashable {
        let pid: pid_t
        let startedAt: UInt64
    }

    /// One process instance for the path caches, from `proc_bsdinfo`'s start time, which is available before
    /// `proc_pid_rusage` is called.
    private struct ProcessIdentity: Hashable {
        let pid: pid_t
        let seconds: UInt64
        let microseconds: UInt64
    }

    private let timebase = AppHealthMachTimebase.current()
    private let userID = getuid()
    private var previous: [ProcessKey: AppHealthProcessCounters] = [:]
    private var previousTickAt: UInt64?
    /// Executable paths of processes attributed by path; an empty string records a failed read.
    private var paths: [ProcessIdentity: String] = [:]
    /// The path-based owner of each such process. Cleared whenever the set of watched bundles changes.
    private var pathOwners: [ProcessIdentity: String?] = [:]
    private var bundles: [(path: String, app: String)] = []
    /// Raw bundle path → the same path with symlinks resolved, to compare with `proc_pidpath`'s real paths.
    private var resolvedBundlePaths: [String: String] = [:]

    init() {}

    func resetBaselines() {
        previous.removeAll()
        previousTickAt = nil
    }

    func sample(_ apps: [AppHealthWatchedApp]) -> AppHealthSamplerResult {
        let costStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let now = mach_absolute_time()
        let mainProcesses = Dictionary(apps.map { ($0.pid, $0.bundleID) }, uniquingKeysWith: { first, _ in first })
        updateBundles(apps)

        var table: [pid_t: (parent: pid_t, identity: ProcessIdentity)] = [:]
        for pid in Self.allProcessIDs() where pid > 0 {
            guard let info = Self.bsdInfo(pid), info.pbi_uid == userID else { continue }
            table[pid] = (pid_t(bitPattern: info.pbi_ppid),
                          ProcessIdentity(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec))
        }
        let parents = table.mapValues(\.parent)

        var usage: [String: AppHealthAppUsage] = [:]
        var pids: [String: Set<pid_t>] = [:]
        var current: [ProcessKey: AppHealthProcessCounters] = [:]
        for (pid, entry) in table {
            let owner: AppHealthAttribution.Owner
            if let found = AppHealthAttribution.owner(of: pid, parents: parents, mainProcesses: mainProcesses) {
                owner = found
            } else if let app = pathOwner(of: entry.identity) {
                owner = AppHealthAttribution.Owner(app: app, role: .helper)
            } else {
                continue
            }
            guard let rusage = Self.resourceUsage(pid) else { continue }
            let key = ProcessKey(pid: pid, startedAt: rusage.ri_proc_start_abstime)
            let counters = AppHealthProcessCounters(
                cpuSeconds: timebase.seconds(rusage.ri_user_time &+ rusage.ri_system_time),
                idleWakeups: rusage.ri_pkg_idle_wkups, energy: rusage.ri_energy_nj)
            let delta = AppHealthDeltaMath.delta(current: counters, previous: previous[key],
                                                 startedAt: key.startedAt, previousTickAt: previousTickAt)
            current[key] = counters
            usage[owner.app, default: AppHealthAppUsage()]
                .add(delta, footprint: rusage.ri_phys_footprint, reportsEnergy: counters.energy > 0,
                     isMain: owner.role == .main)
            pids[owner.app, default: []].insert(pid)
        }

        let live = Set(table.values.map(\.identity))
        paths = paths.filter { live.contains($0.key) }
        pathOwners = pathOwners.filter { live.contains($0.key) }
        let interval = previousTickAt.map { timebase.seconds(now &- $0) }
        previous = current
        previousTickAt = now
        let cost = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) &- costStart) / 1_000_000
        return AppHealthSamplerResult(interval: interval, usage: usage, pids: pids, costMilliseconds: cost)
    }

    /// Keeps the bundle list current and drops path-based owners when it changes, since an app launching or
    /// quitting can change which bundle a helper's path falls in. Cached paths stay valid.
    private func updateBundles(_ apps: [AppHealthWatchedApp]) {
        let next = apps.compactMap { app -> (path: String, app: String)? in
            guard let raw = app.bundlePath else { return nil }
            let resolved = resolvedBundlePaths[raw] ?? URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
            resolvedBundlePaths[raw] = resolved
            return (resolved, app.bundleID)
        }
        let changed = next.count != bundles.count
            || zip(next, bundles).contains { $0.path != $1.path || $0.app != $1.app }
        guard changed else { return }
        bundles = next
        pathOwners.removeAll()
        let rawPaths = Set(apps.compactMap(\.bundlePath))
        resolvedBundlePaths = resolvedBundlePaths.filter { rawPaths.contains($0.key) }
    }

    private func pathOwner(of identity: ProcessIdentity) -> String? {
        if let cached = pathOwners[identity] { return cached }
        let path: String
        if let known = paths[identity] {
            path = known
        } else {
            path = Self.executablePath(identity.pid) ?? ""
            paths[identity] = path
        }
        let owner = path.isEmpty ? nil : AppHealthAttribution.owner(executablePath: path, bundles: bundles)
        pathOwners[identity] = .some(owner)
        return owner
    }

    // MARK: - libproc

    private static func allProcessIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Headroom for processes that start between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(min(Int(count), pids.count)))
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func resourceUsage(_ pid: pid_t) -> rusage_info_v6? {
        var info = rusage_info_v6()
        // `proc_pid_rusage` takes the struct's address typed as `rusage_info_t *`.
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return result == 0 ? info : nil
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 × MAXPATHLEN; the macro does not import into Swift.
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
