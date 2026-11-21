import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import NaturalLanguage

/// `LookoutBench queries`: writes known-item eval cases (`EvalCase`) for the files in an index, with Apple's
/// on-device model.
///
/// For each file the model sees what Lookout read from it (page, chunk and OCR text, as the index stores it), the
/// picture itself for images and screenshots, and the first page for a PDF without text. It writes up to eight
/// queries: four German and four English, one per `EvalCase.Style`. Each language gets its own session, instructed
/// and prompted in that language with worked examples: asked for both in one answer, the model drifted into one
/// language and wrote bare one-word queries ("Screenshot", "Oktober 2026"). Queries that can't single out a file
/// or come back in the wrong language are dropped (`valid`).
///
/// Nothing leaves the Mac. Files are visited in a stable shuffled order, at most `cap` per `--root`, and a file that
/// already has cases in `--out` is skipped, so a stopped run resumes. The model refuses some files (its guardrails);
/// those are skipped and counted.
enum QueriesCommand {
    /// What Lookout read from a file, as much as the prompt has room for. At about 3.5 characters a token this
    /// leaves half of the 8,192-token context for the instructions, the picture and the answer.
    static let textBudget = 6_000

    static func run(index: URL, out: URL, roots: [URL], cap: Int, limit: Int?) async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw BenchFailure("Apple's on-device model isn't available: \(SystemLanguageModel.default.availability)")
        }
        guard let store = try IndexStore.openReadOnly(directory: index) else {
            throw BenchFailure("no index in \(index.path)")
        }
        let done = Set((try? EvalCase.load([out]))?.flatMap(\.expect) ?? [])
        let files = try pick(try candidates(store), roots: roots.map { EvalCommand.realPath($0.path) }, cap: cap)
        let todo = files.filter { !done.contains($0.path) }.prefix(limit ?? .max)
        let asOf = ISO8601DateFormatter.day.string(from: Date())
        print("\(files.count) files picked, \(files.count - todo.count) already have cases; writing \(todo.count)")

        let writer = try LineWriter(out)
        var written = 0, refused = 0, empty = 0
        let start = Date()
        for (number, file) in todo.enumerated() {
            let text = try self.text(of: file.id, store)
            let picture = try self.picture(of: file, hasText: !text.isEmpty)
            guard !text.isEmpty || picture != nil else {
                empty += 1
                continue
            }
            do {
                let generated = try await generate(file: file, text: text, picture: picture)
                let words = Set(Searcher.terms(text + " " + file.path))
                for item in generated {
                    let terms = Searcher.terms(item.query)
                    let overlap = terms.isEmpty ? nil : Double(terms.filter(words.contains).count) / Double(terms.count)
                    try writer.write(EvalCase(q: item.query, expect: [file.path], lang: item.lang, style: item.style.rawValue,
                                              source: "fm", split: EvalCase.split(for: file.path), overlap: overlap,
                                              asOf: asOf).line())
                    written += 1
                }
            } catch {
                refused += 1
                print("  skipped \((file.path as NSString).lastPathComponent): \(error)")
            }
            if (number + 1) % 25 == 0 {
                print(String(format: "  %d/%d files, %d cases, %.1f s a file", number + 1, todo.count, written,
                             Date().timeIntervalSince(start) / Double(number + 1)))
            }
        }
        print("wrote \(written) cases to \(out.path); \(refused) files refused or failed, \(empty) without text")
    }

    // MARK: Generation

    /// One language's queries for a file. The summary comes first: the model writes fields in order, so it settles
    /// what sets the file apart before it writes the queries that have to find it.
    @Generable
    struct LanguageQueries {
        @Guide(description: "One sentence: what the file is, and what sets it apart from similar files.")
        var summary: String
        @Guide(description: "A vague memory of the file's topic, 3 to 6 words, in your own words.")
        var vague: String
        @Guide(description: "The kind of file plus its topic, 3 to 7 words.")
        var kind: String
        @Guide(description: "One exact detail from the file: a name, an amount, a number, a code or a place, 1 to 4 words.")
        var detail: String
        @Guide(description: "When the file is from plus its topic, 3 to 7 words.")
        var date: String

        var queries: [(String, EvalCase.Style)] { [(vague, .vague), (kind, .kind), (detail, .detail), (date, .date)] }
    }

    /// The instructions for each language, written in it, with examples: the small model follows the examples' length
    /// and language far better than a rule ("3 to 6 words") alone.
    static let instructions: [(lang: String, text: String)] = [
        ("en", """
            You write the search queries a person types into their Mac's file search to find one specific file they \
            remember. People search from memory: short, a little vague, in their own words. They never type the file \
            name and never copy whole sentences from the file. Every query must include the file's topic, so it fits \
            this file better than similar files. Write everything in English.

            Examples for an electricity bill from a utility in Kiel, from January 2024:
            vague: "power bill last winter"
            kind: "PDF electricity invoice utility"
            detail: "4,812 kWh"
            date: "electricity bill from early 2024"

            Examples for a screenshot of a chat about moving house, from last month:
            vague: "chat about who helps with the move"
            kind: "screenshot of moving chat"
            detail: "van on Saturday"
            date: "moving chat from last month"
            """),
        ("de", """
            Du schreibst Suchanfragen, die ein Mensch in die Dateisuche seines Macs tippt, um eine bestimmte Datei \
            wiederzufinden, an die er sich erinnert. Menschen suchen aus dem Gedächtnis: kurz, etwas ungenau, in \
            eigenen Worten. Sie tippen nie den Dateinamen und kopieren nie ganze Sätze aus der Datei. Jede Anfrage \
            muss das Thema der Datei enthalten, sodass sie zu dieser Datei besser passt als zu ähnlichen Dateien. \
            Schreibe alles auf Deutsch.

            Beispiele für eine Stromrechnung der Stadtwerke Kiel aus dem Januar 2024:
            vage: "Strom Abrechnung letzter Winter"
            Art: "PDF Rechnung Stadtwerke Strom"
            Detail: "4.812 kWh"
            Datum: "Stromrechnung von Anfang 2024"

            Beispiele für einen Screenshot eines Chats über einen Umzug, vom letzten Monat:
            vage: "Chat wer beim Umzug hilft"
            Art: "Bildschirmfoto Chat Umzug Helfer"
            Detail: "Transporter Samstag"
            Datum: "Umzugschat vom letzten Monat"
            """),
    ]

    /// A query kept, and its language and style.
    struct Generated {
        let query: String
        let lang: String
        let style: EvalCase.Style
    }

    /// Both languages' queries for a file, English first, each checked (`valid`); a language whose answer fails the
    /// check twice is left out.
    private static func generate(file: IndexedFile, text: String, picture: CGImage?) async throws
        -> [Generated] {
        var kept: [Generated] = []
        var lastError: Error?
        var summary: String?
        for (lang, instructions) in instructions {
            // A picture with German instructions trips the guardrails now and then ("May contain unsafe content")
            // where the same picture in English passes; the second try then describes it with the English summary.
            for attempt in 0..<2 {
                let fallback = attempt == 1 && picture != nil && summary != nil
                do {
                    let answer = try await ask(lang: lang, instructions: instructions, file: file,
                                               text: fallback ? "\(summary!)\n\(text)" : text,
                                               picture: fallback ? nil : picture)
                    if lang == "en" { summary = answer.summary }
                    var valid: [Generated] = []
                    for (query, style) in answer.queries {
                        guard let query = clean(query) else { continue }
                        if Self.valid(query, lang: lang, style: style) {
                            valid.append(Generated(query: query, lang: lang, style: style))
                        } else {
                            rejected(query, lang: lang, style: style)
                        }
                    }
                    guard valid.count >= 3 else { continue }
                    kept += valid
                    break
                } catch {
                    lastError = error
                    FileHandle.standardError.write(Data("    \(lang) failed: \(error)\n".utf8))
                }
            }
        }
        if kept.isEmpty, let lastError { throw lastError }
        return kept
    }

    /// The model with the guardrails meant for working on given content, which refuse fewer harmless pictures.
    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    private static func ask(lang: String, instructions: String, file: IndexedFile, text: String, picture: CGImage?)
        async throws -> LanguageQueries {
        let session = LanguageModelSession(model: model, instructions: instructions)
        // In words, as people say it: a date given as 2026-10-15 came back verbatim in the queries.
        let date = file.date.formatted(Date.FormatStyle(date: .long, time: .omitted)
            .locale(Locale(identifier: lang == "de" ? "de_DE" : "en_US")))
        let today = Date().formatted(Date.FormatStyle(date: .long, time: .omitted)
            .locale(Locale(identifier: lang == "de" ? "de_DE" : "en_US")))
        let kind = switch (file.kind, lang) {
        case (.screenshot, "de"): "ein Bildschirmfoto (Screenshot)"
        case (.image, "de"): "ein Foto oder Bild"
        case (.pdf, "de"): "ein PDF"
        case (.doc, "de"): "ein Dokument oder eine Notiz"
        case (.screenshot, _): "a screenshot"
        case (.image, _): "a photo or picture"
        case (.pdf, _): "a PDF"
        case (.doc, _): "a document or note"
        }
        let response = try await session.respond(generating: LanguageQueries.self) {
            lang == "de" ? "Heute ist der \(today). Die Datei ist \(kind) vom \(date)."
                : "Today is \(today). The file is \(kind) from \(date)."
            if let picture { Attachment(picture) }
            if !text.isEmpty { (lang == "de" ? "Inhalt der Datei:\n" : "What the file says:\n") + text }
        }
        return response.content
    }

    /// Logs a dropped query to stderr, so the log shows what the checks throw away.
    private static func rejected(_ query: String, lang: String, style: EvalCase.Style) {
        FileHandle.standardError.write(Data("    dropped \(lang) \(style.rawValue): \(query)\n".utf8))
    }

    private static func clean(_ query: String) -> String? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"„“”'.")))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Whether a query can find one file: enough words for its style (an exact detail may be one), not only a kind
    /// of file or a date, and, when it's long enough to tell, in the language asked for.
    static func valid(_ query: String, lang: String, style: EvalCase.Style) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard words.count >= (style == .detail ? 1 : 2), words.count <= 10 else { return false }
        if style == .detail, query.filter({ $0.isLetter || $0.isNumber }).count < 3 { return false }
        if style != .detail, Searcher.terms(query).allSatisfy({ generic.contains($0) || $0.allSatisfy(\.isNumber) }) {
            return false
        }
        guard words.count >= 3 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(query)
        return recognizer.dominantLanguage?.rawValue == lang
    }

    /// Words that say what kind of file or when, but nothing about which one.
    private static let generic: Set<String> = [
        "screenshot", "bildschirmfoto", "pdf", "foto", "photo", "bild", "picture", "image", "dokument", "document",
        "notiz", "note", "datei", "file", "januar", "februar", "märz", "april", "mai", "juni", "juli", "august",
        "september", "oktober", "november", "dezember", "january", "february", "march", "may", "june", "july",
        "october", "december", "letzten", "letzte", "last", "monat", "month", "jahr", "year", "vom", "aus",
    ]

    // MARK: Files

    struct IndexedFile {
        let id: Int64
        let path: String
        let kind: FileKind
        /// When the picture was taken, else when the file was last changed.
        let date: Date
    }

    private static func candidates(_ store: IndexStore) throws -> [IndexedFile] {
        var files: [IndexedFile] = []
        try store.db.query("""
            SELECT id, path, kind, mtime, json_extract(info, '$.taken') FROM files WHERE state IN ('done', 'partial')
            """) { row in
            let taken = row.text(4).flatMap(exifDate.date(from:))
            files.append(IndexedFile(id: row.int(0), path: row.text(1) ?? "",
                                     kind: FileKind(rawValue: row.text(2) ?? "") ?? .doc,
                                     date: taken ?? Date(timeIntervalSince1970: row.double(3))))
        }
        return files
    }

    /// EXIF's DateTimeOriginal ("2024:07:14 18:03:22"), as `info.taken` keeps it.
    private static let exifDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    /// At most `cap` files under each root, in a stable shuffled order (`EvalCase.split`'s hash, salted).
    private static func pick(_ files: [IndexedFile], roots: [String], cap: Int) throws -> [IndexedFile] {
        guard !roots.isEmpty else { throw BenchFailure("missing --root <folder>") }
        let shuffled = files.sorted { stableHash($0.path) < stableHash($1.path) }
        return roots.flatMap { root in
            shuffled.filter { $0.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") }.prefix(cap)
        }
    }

    private static func stableHash(_ path: String) -> UInt64 {
        var hash: UInt64 = 0x84222325cbf29ce4
        for byte in path.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// The file's page, chunk and OCR text in reading order, as written, up to `textBudget` characters.
    private static func text(of file: Int64, _ store: IndexStore) throws -> String {
        var text = ""
        try store.db.scan("""
            SELECT coalesce(fts.original, fts.body) FROM segments s JOIN fts ON fts.rowid = s.id
            WHERE s.file = ? AND s.kind IN ('page', 'chunk', 'ocr') ORDER BY s.id
            """, [.int(file)]) { row in
            if let part = row.text(0), !part.isEmpty { text += (text.isEmpty ? "" : "\n") + part }
            return text.count < textBudget
        }
        return String(text.prefix(textBudget))
    }

    /// The picture the model looks at: the image itself, or a PDF's first page when it has no text.
    private static func picture(of file: IndexedFile, hasText: Bool) throws -> CGImage? {
        let url = URL(fileURLWithPath: file.path)
        switch file.kind {
        case .image, .screenshot:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        case .pdf where !hasText:
            guard let page = CGPDFDocument(url as CFURL)?.page(at: 1) else { return nil }
            let box = page.getBoxRect(.mediaBox)
            let scale = 1024 / max(box.width, box.height)
            let size = CGSize(width: (box.width * scale).rounded(), height: (box.height * scale).rounded())
            guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.setFillColor(.white)
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(page)
            return context.makeImage()
        default:
            return nil
        }
    }
}

extension ISO8601DateFormatter {
    /// yyyy-MM-dd in the current time zone.
    static let day: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }()
}
