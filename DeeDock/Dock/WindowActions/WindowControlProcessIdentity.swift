import AppKit
import Darwin

extension NSRunningApplication {
    /// Finder can have no AppKit launch date. The kernel start time still distinguishes
    /// process lifetimes, including PID reuse. Failure to read either identity stays closed.
    nonisolated var windowControlLaunchDate: Date? {
        if let launchDate { return launchDate }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
}
