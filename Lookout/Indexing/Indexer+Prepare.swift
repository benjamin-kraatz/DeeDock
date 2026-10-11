// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// Preparing a job: reading and decoding its files on the preparation queue, one job ahead of the model. Files only:
/// no database, no model, so it can run beside `commit` on another thread.
nonisolated extension Indexer {
    /// Files read and embedded together (images 8 at a time, other files one by one), or one step of a long file
    /// (`step`: the pages of a PDF or the chunks of a document to read, from 0). The first step comes with the file.
    struct Job: Sendable {
        let files: [FileRecord]
        var step: Range<Int>?
    }

    /// A job read from disk and decoded, ready for the model. Its scratch files live in `folder`.
    struct Prepared: Sendable {
        let batch: [FileRecord]
        let step: Range<Int>?                // a long file's later step (`Job.step`)
        let folder: URL
        var outcomes: [Int: Outcome] = [:]   // files already settled (skipped or failed while reading)
        var payload = Payload.nothing
    }

    struct Outcome: Sendable {
        let state: String
        let detail: String?
    }

    enum Payload: Sendable {
        case nothing
        case images(screenshot: Bool, ready: [ReadyImage])
        /// `read`: the pages read (from 0) of the PDF's `total`.
        case pdf(pages: [PDFExtractor.Page], read: Range<Int>, total: Int, title: String?)
        /// `chunks`: the ones in `read` (from 0) of the document's `total` (counted up to `IndexOptions.maxChunks` + 1).
        case doc(chunks: [String], read: Range<Int>, total: Int, characters: Int)
    }

    struct ReadyImage: Sendable {
        let slot: Int
        let image: ImageExtractor.Prepared
        let ocr: String
    }

    /// A batch being prepared on the preparation queue.
    final class PendingBatch: @unchecked Sendable {
        private let ready = DispatchSemaphore(value: 0)
        private var value: Prepared?

        fileprivate func fulfill(_ prepared: Prepared) {
            value = prepared
            ready.signal()
        }

        /// Blocks until it's ready. Call once.
        func wait() -> Prepared {
            ready.wait()
            return value!
        }
    }

    /// The preparation thread: utility QoS, as the service's work queue.
    private static let preparing = DispatchQueue(label: "Lookout.Index.prepare", qos: .utility)

    func prepare(_ job: Job) -> PendingBatch {
        let pending = PendingBatch()
        let (options, folder) = (options, scratch.appendingPathComponent(UUID().uuidString))
        Self.preparing.async {
            pending.fulfill(Self.prepare(job, options: options, into: folder))
        }
        return pending
    }

    static func prepare(_ job: Job, options: IndexOptions, into folder: URL) -> Prepared {
        let batch = job.files
        var prepared = Prepared(batch: batch, step: job.step, folder: folder)
        let url = URL(fileURLWithPath: batch[0].path)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            switch batch[0].kind {
            case .image, .screenshot:
                let screenshot = batch[0].kind == .screenshot
                var ready: [ReadyImage] = []
                for (slot, file) in batch.enumerated() {
                    let url = URL(fileURLWithPath: file.path)
                    do {
                        let image = try ImageExtractor.prepare(url, maxPixel: screenshot ? 1536 : 1024,
                                                               minSide: options.minImageSide, to: folder,
                                                               png: screenshot)
                        let ocr = screenshot ? ImageExtractor.fullImage(url).map(ScreenshotOCR.text(in:)) ?? "" : ""
                        ready.append(ReadyImage(slot: slot, image: image, ocr: ocr))
                    } catch {
                        if case ExtractError.tooSmall = error {
                            prepared.outcomes[slot] = Outcome(state: "skipped", detail: "\(error)")
                        } else {
                            prepared.outcomes[slot] = Outcome(state: "failed", detail: "\(error)")
                        }
                    }
                }
                prepared.payload = .images(screenshot: screenshot, ready: ready)
            case .pdf:
                // Long PDFs (books) get their first pages now and the rest after everything else.
                var wanted = 0..<0
                let read = try PDFExtractor.pages(of: url, range: { total in
                    wanted = (job.step ?? (total > options.bigPDFPages ? 0..<options.pdfStep : 0..<options.maxPages))
                        .clamped(to: 0..<min(total, options.maxPages))
                    return wanted
                }, minText: options.minPageText, renderPixels: 1400, to: folder)
                prepared.payload = .pdf(pages: read.pages, read: wanted, total: read.total, title: read.title)
            case .doc:
                // The chunks are cut the same way every time, so a later step goes on where the last one stopped.
                let text = try DocExtractor.text(of: url)
                let chunks = DocExtractor.chunks(text, limit: options.maxChunks + 1)
                let read = (job.step ?? 0..<options.docStep).clamped(to: 0..<min(chunks.count, options.maxChunks))
                prepared.payload = .doc(chunks: Array(chunks[read]), read: read, total: chunks.count,
                                        characters: text.count)
            }
        } catch {
            for slot in batch.indices where prepared.outcomes[slot] == nil {
                prepared.outcomes[slot] = Outcome(state: "failed", detail: "\(error)")
            }
            prepared.payload = .nothing
        }
        return prepared
    }
}
