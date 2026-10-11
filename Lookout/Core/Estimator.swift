// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CoreGraphics
import CoreServices
import Foundation

/// First-index time and index size from metadata alone: counts come from the crawl, PDF page counts from Spotlight
/// (falling back to the file header when Spotlight hasn't seen a file yet), so nothing is decoded. For onboarding's
/// folder list.
nonisolated enum Estimator {
    /// Seconds of indexing per unit, measured 2026-10-07 by DigUp on an M4 Pro with llama.cpp (Q8_0), reading files
    /// while the model embeds (a full index of its 365-file testbed: 160 s, per-kind sums below).
    struct Costs: Sendable {
        var image = 0.12              // 140 tokens, decode included
        var screenshot = 0.32         // 280 tokens; its OCR (0.24 s) runs alongside and sets the pace
        var pdfPage = 0.09            // text pages are cheap, rendered scans cost an image
        var docChunk = 0.095
        init() {}
    }

    /// Bytes of index per unit. DigUp measured its code index (2026-10-09: 6.3 MB for 1,245 stretches of 2 MB of
    /// code): ~2.4 bytes per character of keyword text and ~1,600 bytes per vector row. The text per unit is a guess
    /// from the chunk size (`DocExtractor.chunks`: 1,800 characters with 200 shared) and typical pages, not measured.
    enum Size {
        static let perCharacter = 2.4
        static let perVector = 1600.0
        /// The `files` row, the name segment and its keyword row.
        static let perFile = 400.0
        static let charactersPerChunk = 1600.0
        static let charactersPerPage = 2000.0
        static let charactersPerScreenshot = 600.0   // OCR text
    }

    /// What the first pass (and the later one, for long files) will take.
    struct Estimate: Sendable {
        var files: [FileKind: Int] = [:]
        var pdfPages = 0           // pages the first pass will read
        var pdfPagesTotal = 0
        var docChunks = 0          // chunks the first pass will read
        var seconds = 0.0          // the first pass
        /// Long PDFs and documents, which get their first step in the first pass, and how long the rest of them takes
        /// once everything else is in (`Indexer.finishLongFiles`).
        var longFiles = 0
        var laterSeconds = 0.0
        /// About how big the index gets on disk once everything is read, later pass included.
        var bytes = 0.0

        init() {}

        var fileCount: Int { files.values.reduce(0, +) }

        static func + (a: Estimate, b: Estimate) -> Estimate {
            var sum = a
            sum.files.merge(b.files, uniquingKeysWith: +)
            sum.pdfPages += b.pdfPages
            sum.pdfPagesTotal += b.pdfPagesTotal
            sum.docChunks += b.docChunks
            sum.seconds += b.seconds
            sum.longFiles += b.longFiles
            sum.laterSeconds += b.laterSeconds
            sum.bytes += b.bytes
            return sum
        }
    }

    static func estimate(_ candidates: [Candidate], options: IndexOptions, costs: Costs = Costs()) -> Estimate {
        var estimate = Estimate()
        for file in candidates {
            estimate.files[file.kind, default: 0] += 1
            estimate.bytes += Size.perFile
            switch file.kind {
            case .image:
                estimate.seconds += costs.image
                estimate.bytes += Size.perVector
            case .screenshot:
                estimate.seconds += costs.screenshot
                estimate.bytes += Size.perVector + Size.charactersPerScreenshot * Size.perCharacter
            case .pdf:
                let total = pages(of: file.path)
                let all = min(total, options.maxPages)
                let first = total > options.bigPDFPages ? min(options.pdfStep, all) : all
                estimate.pdfPagesTotal += total
                estimate.pdfPages += first
                estimate.seconds += Double(first) * costs.pdfPage
                estimate.bytes += Double(all) * (Size.perVector + Size.charactersPerPage * Size.perCharacter)
                if all > first {
                    estimate.longFiles += 1
                    estimate.laterSeconds += Double(all - first) * costs.pdfPage
                }
            case .doc:
                let all = max(1, min(options.maxChunks, Int(file.size / 2000)))
                let first = min(all, options.docStep)
                estimate.docChunks += first
                estimate.seconds += Double(first) * costs.docChunk
                estimate.bytes += Double(all) * (Size.perVector + Size.charactersPerChunk * Size.perCharacter)
                if all > first {
                    estimate.longFiles += 1
                    estimate.laterSeconds += Double(all - first) * costs.docChunk
                }
            }
        }
        return estimate
    }

    /// Estimates for each subfolder one level down, and for the files right in `folder` (under its own path), from
    /// the same look at each file: the folder lists show where a big first pass comes from.
    /// Subfolders are named under `folder` as given, though the walk reports real paths (/private/var for /var).
    static func estimates(bySubfolder candidates: [Candidate], of folder: String, options: IndexOptions,
                          costs: Costs = Costs()) -> [String: Estimate] {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        let real = FolderSelection.realPath(folder) + "/"
        var groups: [String: [Candidate]] = [:]
        for file in candidates {
            let rest = file.path.hasPrefix(prefix) ? file.path.dropFirst(prefix.count)
                : file.path.hasPrefix(real) ? file.path.dropFirst(real.count) : nil
            let key = rest.flatMap { rest in rest.firstIndex(of: "/").map { prefix + rest[..<$0] } } ?? folder
            groups[key, default: []].append(file)
        }
        return groups.mapValues { estimate($0, options: options, costs: costs) }
    }

    static func pages(of path: String) -> Int {
        if let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
           let pages = (MDItemCopyAttribute(item, kMDItemNumberOfPages) as? NSNumber)?.intValue, pages > 0 {
            return pages
        }
        return CGPDFDocument(URL(fileURLWithPath: path) as CFURL)?.numberOfPages ?? 1
    }
}
