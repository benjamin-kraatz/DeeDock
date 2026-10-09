import Darwin
import Foundation

/// Pause and cancel switches for one running transfer, shared between the main actor and the
/// worker thread.
///
/// The worker checks `waitWhilePaused()` from every `copyfile(3)` status callback, so a pause
/// blocks the copy mid-file on its dispatch thread (never a Swift concurrency thread) and a
/// cancel makes the callback return `COPYFILE_QUIT`.
nonisolated final class HubFileTransferControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused: Bool
    private var cancelled = false

    init(paused: Bool = false) {
        self.paused = paused
    }

    /// Holds the worker at its next status callback until `resume()` or `cancel()`.
    func pause() {
        condition.lock()
        paused = true
        condition.unlock()
    }

    /// Lets a paused worker continue.
    func resume() {
        condition.lock()
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    /// Stops the worker at its next status callback, waking it if it is paused.
    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    /// Blocks while paused. Returns false when the transfer was cancelled.
    func waitWhilePaused() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while paused && !cancelled { condition.wait() }
        return !cancelled
    }
}

/// Performs one copy or move job synchronously. Runs on `HubFileTransferQueue`'s worker queue.
///
/// Rules:
/// - Never overwrites: every item lands under `HubFileNaming.availableName`, so a copy into the
///   same folder becomes "Name copy" and a move into a folder holding the same name is renamed.
/// - A move whose source shares the destination's volume is a rename (`FileManager.moveItem`)
///   and reports no byte progress. Otherwise the item is copied with `copyfile(3)` and, for a
///   move, the source is deleted only after its copy fully succeeded.
/// - Cancel stops at the next status callback and removes the partially copied item. Items that
///   already finished stay at the destination (and, for a move, are gone from the source), as in
///   Finder.
nonisolated struct HubFileTransferWorker: Sendable {
    /// What the worker reports while running. Progress is throttled to about 30 per second.
    enum Event: Sendable {
        case total(Int64)
        case progress(Int64)
        /// Whether any source lives on another volume than the destination. Sent once, first.
        case crossVolume(Bool)
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case cancelled
        case failed(String)
    }

    let kind: HubFileTransferQueue.Kind
    let sources: [URL]
    let destination: URL
    let control: HubFileTransferControl
    /// Test hook, called on the worker thread from every status callback before the pause check.
    var callbackHook: (@Sendable (HubFileTransferControl) -> Void)?

    static let progressInterval: TimeInterval = 1.0 / 30

    /// Runs the job to completion, cancellation, or the first error.
    func run(report: @escaping @Sendable (Event) -> Void) -> Outcome {
        let destinationVolume = HubDirectoryLister.volumeIdentifier(of: destination)
        let sameVolume = sources.map { source in
            destinationVolume != nil && HubDirectoryLister.volumeIdentifier(of: source) == destinationVolume
        }
        let plans = zip(sources, sameVolume).map { (url: $0, rename: kind == .move && $1) }
        report(.crossVolume(sameVolume.contains(false)))

        // Size up front so the bar moves at an even rate across items.
        var sizes: [Int64] = []
        for plan in plans {
            guard !control.isCancelled else { return .cancelled }
            sizes.append(plan.rename ? 0 : Self.byteCount(of: plan.url, control: control))
        }
        report(.total(sizes.reduce(0, +)))

        var completed: Int64 = 0
        for (index, plan) in plans.enumerated() {
            guard control.waitWhilePaused() else { return .cancelled }
            let name = HubFileNaming.availableName(for: plan.url.lastPathComponent, in: destination) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let target = destination.appendingPathComponent(name)

            if plan.rename {
                do {
                    try FileManager.default.moveItem(at: plan.url, to: target)
                } catch {
                    return .failed(Self.message(.move, item: plan.url, reason: error.localizedDescription))
                }
                continue
            }

            let result = copy(plan.url, to: target, base: completed, size: sizes[index], report: report)
            switch result {
            case .completed:
                completed += sizes[index]
                report(.progress(completed))
            case .cancelled:
                try? FileManager.default.removeItem(at: target)
                return .cancelled
            case .failed(let reason):
                try? FileManager.default.removeItem(at: target)
                return .failed(Self.message(kind, item: plan.url, reason: reason))
            }

            if kind == .move {
                do {
                    try FileManager.default.removeItem(at: plan.url)
                } catch {
                    return .failed(Self.message(.move, item: plan.url, reason: error.localizedDescription))
                }
            }
        }
        return .completed
    }

    // MARK: - copyfile

    private func copy(_ source: URL, to target: URL, base: Int64, size: Int64,
                      report: @escaping @Sendable (Event) -> Void) -> Outcome {
        guard let state = copyfile_state_alloc() else { return .failed(String(cString: strerror(ENOMEM))) }
        defer { copyfile_state_free(state) }
        let context = CopyContext(control: control, hook: callbackHook, base: base, limit: size, report: report)
        let callback: copyfile_callback_t = { what, stage, state, source, _, context in
            guard let context else { return COPYFILE_CONTINUE }
            let copy = Unmanaged<CopyContext>.fromOpaque(context).takeUnretainedValue()
            return copy.handle(what: what, stage: stage, state: state, source: source)
        }
        // `copyfile_state_set` takes the callback and context as untyped pointers. The context
        // stays alive through `withExtendedLifetime` until `copyfile` has returned.
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())
        let status = withExtendedLifetime(context) {
            copyfile(source.path, target.path, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE))
        }
        if status == 0, !context.failed { return .completed }
        if control.isCancelled { return .cancelled }
        let code = context.errorCode != 0 ? context.errorCode : errno
        return .failed(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO).localizedDescription)
    }

    /// State shared with the C status callback through its context pointer.
    private final class CopyContext {
        let control: HubFileTransferControl
        let hook: (@Sendable (HubFileTransferControl) -> Void)?
        let report: @Sendable (Event) -> Void
        /// Bytes of earlier items in this job.
        let base: Int64
        /// This item's precomputed size; reported progress never exceeds `base + limit`.
        let limit: Int64
        /// Bytes of files finished inside this item (recursive copies).
        var finishedFiles: Int64 = 0
        /// Bytes copied of the file in progress.
        var current: Int64 = 0
        var lastReport = Date.distantPast
        var failed = false
        var errorCode: Int32 = 0

        init(control: HubFileTransferControl, hook: (@Sendable (HubFileTransferControl) -> Void)?,
             base: Int64, limit: Int64, report: @escaping @Sendable (Event) -> Void) {
            self.control = control
            self.hook = hook
            self.base = base
            self.limit = limit
            self.report = report
        }

        func handle(what: Int32, stage: Int32, state: copyfile_state_t?, source: UnsafePointer<CChar>?) -> Int32 {
            if stage == COPYFILE_ERR {
                failed = true
                errorCode = errno
                return COPYFILE_QUIT
            }
            if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                current = Int64(copied)
            } else if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
                // Cloned files report no data progress, so count each finished file by its size.
                var info = stat()
                if let source, lstat(source, &info) == 0 { finishedFiles += Int64(info.st_size) }
                current = 0
            }
            publish()
            hook?(control)
            return control.waitWhilePaused() ? COPYFILE_CONTINUE : COPYFILE_QUIT
        }

        private func publish() {
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= HubFileTransferWorker.progressInterval else { return }
            lastReport = now
            report(.progress(base + min(limit, finishedFiles + current)))
        }
    }

    // MARK: - Sizing and messages

    /// Logical bytes `copyfile` will write for `url`: the file's size, or the sum over a folder or
    /// package including hidden files. Links count as themselves. Walks off the main actor.
    static func byteCount(of url: URL, control: HubFileTransferControl? = nil) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return Int64(values.fileSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if control?.isCancelled == true { break }
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func message(_ kind: HubFileTransferQueue.Kind, item: URL, reason: String) -> String {
        let name = FileManager.default.displayName(atPath: item.path)
        return switch kind {
        case .copy: String(localized: .hubFilesTransferCopyFailed(name, reason))
        case .move: String(localized: .hubFilesTransferMoveFailed(name, reason))
        }
    }
}
