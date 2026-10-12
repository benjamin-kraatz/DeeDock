// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// Keeps the index in step with the chosen folders, then extracts and embeds whatever is pending.
///
/// Model work goes to an `Embedder` (made on first use, freed by `closeWorker`). Extraction (ImageIO, Vision, PDFKit)
/// runs on a second thread one batch ahead, so reading files and embedding them overlap (see `process`).
///
/// Not thread-safe: one thread calls it (the index service's work queue, or the bench's main thread). `shouldStop`
/// callbacks are how another thread asks it to stop between batches.
nonisolated final class Indexer {
    /// One file the first pass has settled.
    struct Event: Sendable {
        let done: Int
        let total: Int
        let path: String
        let kind: FileKind
        let state: String
        /// Seconds per file of the batch it was in.
        let seconds: Double
        let note: String?
    }

    /// One step of the later pass: how far it has got (`done` of the `total` pages and chunks it set out to read, in
    /// `files` files), and the file it just read more of.
    struct Step: Sendable {
        let done: Int
        let total: Int
        let files: Int        // long files not finished yet, this one included until its last step
        let path: String
        let kind: FileKind
        let state: String     // "partial" until the file's last step, then "done"
        let seconds: Double
        let note: String?
    }

    let store: IndexStore
    let options: IndexOptions
    private let makeEmbedder: () throws -> any Embedder
    private(set) var worker: (any Embedder)?
    let scratch: URL
    /// What every file is checked against just before it's read (`QueuedFileGate`): the roots the last sync walked.
    /// Nil until a sync succeeds, and nothing is read until then.
    private(set) var gate: QueuedFileGate?

    /// When set, an index built with another model or other settings is emptied and embedded again (a new version may
    /// bring a new model), and this hears about it. When nil, indexing stops with `fingerprintMismatch`.
    var resetOnModelChange: ((_ indexed: String, _ now: String) -> Void)?

    /// The vector source of the embedders `makeEmbedder` makes, when it's known without starting one (llama.cpp's is:
    /// `LlamaEmbedder.modelInfo`): then `checkModel()` can notice a new model before anything needs embedding.
    var embedderSource: String?

    /// - Throws: The scratch folder can't be created.
    init(store: IndexStore, options: IndexOptions, makeEmbedder: @escaping () throws -> any Embedder) throws {
        self.store = store
        self.options = options
        self.makeEmbedder = makeEmbedder
        // One folder per process (`ScratchFolder`, which a later process clears up after one that died), and one in
        // it per indexer, which clears its own away.
        scratch = ScratchFolder.current.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    deinit {
        worker?.close()
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Frees the embedding model (about 1 GB) until the next file needs it.
    func closeWorker() {
        worker?.close()
        worker = nil
    }

    /// Stops the worker and removes the scratch folder, for a process that's about to exit (deinit won't run then).
    func finish() {
        closeWorker()
        try? FileManager.default.removeItem(at: scratch)
    }

    var workerIsRunning: Bool { worker != nil }

    // MARK: Sync

    /// Crawls `roots` and reconciles the index (`IndexSync`). Only the roots the crawl walked count: a refused one
    /// (`Rules.checkRoots`) keeps its rows rather than looking emptied, and its files aren't read
    /// (`QueuedFileGate`).
    ///
    /// - Parameter found: Hears how many files the walk has found so far while it walks (`Crawler.crawl`).
    func sync(_ roots: [URL], found: ((Int) -> Void)? = nil) throws -> IndexSync.Summary {
        let crawl = Crawler.crawl(roots, options: options, found: found)
        let walked = crawl.roots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let summary = try IndexSync.apply(crawl, roots: walked, to: store)
        gate = QueuedFileGate(roots: crawl.roots, options: options)
        return summary
    }

    // MARK: Run

    /// Processes pending files, most recently used first (`only`: just these files). Long PDFs and documents get their
    /// first step (`IndexOptions.pdfStep` pages, `docStep` chunks) and stay `partial` for `finishLongFiles`.
    /// Per-file problems are recorded on the file; a model that can't run or a settings mismatch stops the run
    /// (pending files stay pending, so the next run resumes). `shouldStop` is asked between batches: pausing, or new
    /// files that should go first. `shouldAbandon` is asked once more after a batch is read and before it's
    /// committed: closing the index drops that batch (its files stay pending) rather than write to the store.
    @discardableResult
    func run(limit: Int? = nil, only ids: Set<Int64>? = nil, shouldStop: () -> Bool = { false },
             shouldAbandon: () -> Bool = { false }, onEvent: (Event) -> Void = { _ in }) throws -> [String: Int] {
        guard gate != nil else { return [:] }   // no sync yet: nothing to check files against
        let queue = try store.pending(limit: limit, only: ids)
        var states: [String: Int] = [:]
        var done = 0
        try process(Self.batches(queue).map { Job(files: $0) }, shouldStop: shouldStop,
                    shouldAbandon: shouldAbandon) { _, job, results, seconds in
            for (offset, file) in job.files.enumerated() {
                let (state, note) = results[offset]
                states[state, default: 0] += 1
                onEvent(Event(done: done + offset + 1, total: queue.count, path: file.path, kind: file.kind,
                              state: state, seconds: seconds, note: note))
            }
            done += job.files.count
        }
        return states
    }

    /// The later pass: reads the rest of long PDFs and documents (`partial` after their first step), in `pending`'s
    /// order, a step at a time. Each step is saved as one transaction, so stopping between steps (pausing, new files
    /// going first) loses nothing, and the next pass goes on from there. It runs once nothing is pending: a book's last
    /// pages matter less than everything else's first ones, and they take a while (0.04–0.2 s a page, 2026-10-09).
    @discardableResult
    func finishLongFiles(shouldStop: () -> Bool = { false }, shouldAbandon: () -> Bool = { false },
                         onStep: (Step) -> Void = { _ in }) throws -> [String: Int] {
        guard gate != nil else { return [:] }   // no sync yet: nothing to check files against
        var jobs: [Job] = []
        for file in try store.unfinished() {
            let info = try store.info(of: file.id)
            let size = file.kind == .pdf ? options.pdfStep : options.docStep
            // Where it stopped (after the last page or chunk stored, should its info not say; nothing stored: the start).
            var start = try info["read_to"].flatMap(Int.init) ?? store.lastPlace(of: file.id) ?? 0
            // At least one step, which settles a file whose length was only guessed.
            let end = max(info["read_end"].flatMap(Int.init) ?? 0, start + 1)
            while start < end {
                jobs.append(Job(files: [file], step: start..<min(start + size, end)))
                start += size
            }
        }
        // Progress counts pages and chunks: what's read once each job is through.
        var through: [Int] = []
        for job in jobs { through.append((through.last ?? 0) + (job.step?.count ?? 0)) }
        var files = Set(jobs.map { $0.files[0].id }).count
        var states: [String: Int] = [:]
        var finished = Set<Int64>()
        try process(jobs, shouldStop: shouldStop, shouldAbandon: shouldAbandon) { index, job, results, seconds in
            let file = job.files[0]
            let (state, note) = results[0]
            if state != "partial", finished.insert(file.id).inserted {
                states[state, default: 0] += 1
                files -= 1
            }
            onStep(Step(done: through[index], total: through.last ?? 0, files: files, path: file.path, kind: file.kind,
                        state: state, seconds: seconds, note: note))
        } skip: { job in
            // Finished sooner than its steps said: a document whose length was guessed, or a file that went unreadable.
            finished.contains(job.files[0].id)
        }
        return states
    }

    /// Runs `jobs` in order until `shouldStop` (asked between jobs), passing each one's results to `committed` (with
    /// its place in `jobs`). Jobs that `skip` turns down when their turn comes are left out. `shouldAbandon` is asked
    /// after a job is read, which can take seconds (OCR, rendered pages), and before its commit writes anything.
    ///
    /// Two stages overlap: while the model embeds one job, the next one is read and decoded on another thread
    /// (images scaled, screenshots OCR'd, PDF pages rendered). OCR alone is ~0.24 s per Retina screenshot, about as
    /// long as embedding it.
    private func process(_ jobs: [Job], shouldStop: () -> Bool, shouldAbandon: () -> Bool = { false },
                         committed: (Int, Job, [(String, String?)], Double) -> Void,
                         skip: (Job) -> Bool = { _ in false }) throws {
        guard let gate else { return }
        var ahead: PendingBatch?
        defer {
            // A job prepared for a run that stopped early: throw its files away.
            if let ahead { try? FileManager.default.removeItem(at: ahead.wait().folder) }
        }
        for (index, job) in jobs.enumerated() {
            guard !shouldStop() else { break }
            let started = Date()
            let prepared = (ahead ?? prepare(job, gate: gate)).wait()
            ahead = index + 1 < jobs.count ? prepare(jobs[index + 1], gate: gate) : nil
            defer { try? FileManager.default.removeItem(at: prepared.folder) }
            guard !skip(job) else { continue }
            guard !shouldAbandon() else { break }
            let results = try commit(prepared)
            committed(index, job, results, Date().timeIntervalSince(started) / Double(job.files.count))
        }
    }

    /// Images and screenshots go to the model 8 at a time; other files one by one. Batches hold consecutive files of
    /// one kind, so recency order (which mixes kinds) makes some image batches smaller than 8.
    static func batches(_ queue: [FileRecord]) -> [[FileRecord]] {
        var batches: [[FileRecord]] = []
        var index = 0
        while index < queue.count {
            var batch = [queue[index]]
            if batch[0].kind == .image || batch[0].kind == .screenshot {
                while index + batch.count < queue.count, batch.count < 8,
                      queue[index + batch.count].kind == batch[0].kind {
                    batch.append(queue[index + batch.count])
                }
            }
            batches.append(batch)
            index += batch.count
        }
        return batches
    }

    // MARK: Model

    /// Compares the index with the current model and settings (`embedderSource`), without starting the model; a
    /// change empties the index (see `resetOnModelChange`) or throws `fingerprintMismatch`. Without a known source the
    /// check waits for the first file to embed.
    func checkModel() throws {
        guard let embedderSource else { return }
        try adopt("\(embedderSource) | \(options.fingerprint)")
    }

    private func adopt(_ fingerprint: String) throws {
        guard let indexed = try store.meta("fingerprint"), indexed != fingerprint else { return }
        guard let resetOnModelChange else { throw IndexerError.fingerprintMismatch(index: indexed, now: fingerprint) }
        // Everything is queued again: a run that's under way goes on with its batch, and later runs take the rest.
        try store.resetAll()
        resetOnModelChange(indexed, fingerprint)
    }

    /// The model, started on first use, after checking (and recording) that the index was built with it.
    func fullWorker() throws -> any Embedder {
        if let worker { return worker }
        let started = try makeEmbedder()
        let fingerprint = "\(started.info.vectorSource) | \(options.fingerprint)"
        do {
            try adopt(fingerprint)
        } catch {
            started.close()
            throw error
        }
        try store.setMeta("fingerprint", fingerprint)
        try store.setMeta("vector_source", started.info.vectorSource)
        worker = started
        return started
    }
}
