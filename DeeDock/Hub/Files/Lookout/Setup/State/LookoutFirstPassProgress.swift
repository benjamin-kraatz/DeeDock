import Foundation

/// The first pass as onboarding's ring shows it, from the index service's status: files read (done, part read,
/// skipped or failed: anything no longer waiting) out of every file the index knows. Counting from the index rather
/// than the current batch keeps the ring from jumping back when the service moves from new files to the backfill.
nonisolated struct LookoutFirstPassProgress: Equatable, Sendable {
    var done: Int
    var total: Int
    /// The service is still walking the folders and hasn't counted anything yet.
    var isCounting: Bool

    init(done: Int, total: Int, isCounting: Bool = false) {
        self.done = done
        self.total = total
        self.isCounting = isCounting
    }

    init(status: LookoutIndexStatus?) {
        guard let status else {
            self.init(done: 0, total: 0, isCounting: true)
            return
        }
        let total = status.counts.files
        let done = max(total - status.counts.pending, 0)
        self.init(done: done, total: total, isCounting: total == 0 && status.activity == .syncing)
    }

    /// 0…1; complete when there's nothing to read.
    var fraction: Double {
        guard total > 0 else { return isCounting ? 0 : 1 }
        return min(max(Double(done) / Double(total), 0), 1)
    }
}
