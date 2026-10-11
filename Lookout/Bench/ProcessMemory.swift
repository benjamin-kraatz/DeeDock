import Darwin
import Metal

/// This process's memory as the system accounts for it.
///
/// `footprint` is `phys_footprint` from `TASK_VM_INFO`, the number Activity Monitor's Memory column and jetsam use:
/// dirty and compressed anonymous memory plus GPU allocations attributed to the process, but not clean file-backed
/// pages such as an mmap'd model that hasn't been written to. `resident` counts those clean pages too. The Metal figure
/// is what the default device reports allocated through it (llama.cpp's buffers live there).
struct ProcessMemory {
    let footprint: UInt64
    /// The highest `footprint` since the process started.
    let peakFootprint: UInt64
    let resident: UInt64
    let metalAllocated: UInt64

    /// A sample now, or nil when `task_info` fails.
    static func sample() -> ProcessMemory? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return ProcessMemory(footprint: info.phys_footprint, peakFootprint: UInt64(clamping: info.ledger_phys_footprint_peak),
                             resident: info.resident_size,
                             metalAllocated: UInt64(MTLCreateSystemDefaultDevice()?.currentAllocatedSize ?? 0))
    }

    /// Megabytes (10^6 bytes), as the decision gate states its limits.
    static func megabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_000_000 }
}
