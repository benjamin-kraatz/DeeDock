import Foundation
import UniformTypeIdentifiers

/// One key fact about a file, as data. Persisted in the analysis cache; turned into a localized
/// chip (`FlixFact`) only when the row draws it, so a language change needs no new analysis.
nonisolated enum FlixFactValue: Codable, Hashable, Sendable {
    case due(Date)
    case validUntil(Date)
    case amount(Double, currency: String)
    case pages(Int)
    case slides(Int)
    case needsSignature
    case signed
    case paid
    /// The amount is collected automatically (direct debit): nothing to pay by hand.
    case autoDebit
}

/// Finds key facts in a file's text and metadata without a model: due dates, totals with their
/// currency, "needs signature" or "signed", "paid" or "auto-debit", and page or slide counts.
///
/// English and German wording only. The fallback: with Apple Intelligence, `FlixDocumentReading`
/// decides a document's facts instead, and this runs only for documents a person reads
/// (``readsFacts(contentType:name:)``) when the model is off, unavailable, or gives no answer. Key words count only as whole words
/// (``wordRanges(of:in:)``): "format" is not "form", "totally" is not "total", "residue" is not "due".
/// German stems end in `*` and match inside words, since German builds compounds around them
/// ("Stromrechnung", "Gesamtbetrag", "Zahlungsfälligkeit").
nonisolated enum FlixFactExtractor {
    /// The most chips one row shows.
    static let limit = 3

    /// Whether a file is a document a person reads (a letter, invoice, contract, note, or table),
    /// not data or code: in JSON, XML, property lists, YAML, logs, configuration, and source code,
    /// dates are timestamps and numbers are sizes and identifiers, never a due date or a total.
    ///
    /// - Parameters:
    ///   - contentType: The item's uniform type identifier, when known; else the name's extension decides.
    static func readsFacts(contentType: String?, name: String) -> Bool {
        let pathExtension = (name as NSString).pathExtension.lowercased()
        if machineExtensions.contains(pathExtension) { return false }
        guard let type = contentType.flatMap(UTType.init) ?? UTType(filenameExtension: pathExtension) else { return true }
        return !machineTypes.contains { type.conforms(to: $0) }
    }

    private static let machineTypes: [UTType] = [.sourceCode, .script, .json, .xml, .propertyList, .yaml, .log]
    /// Data and configuration files macOS has no type for.
    private static let machineExtensions: Set<String> = ["toml", "ini", "cfg", "conf", "env", "lock", "manifest",
                                                         "jsonl", "ndjson", "geojson", "har", "map"]

    /// Whether the text speaks of a payment due date ("due", "fällig", "zahlbar bis", …), as a whole word.
    static func mentionsDueDate(_ text: String) -> Bool {
        let folded = fold(text) as NSString
        return dueWords.contains { !wordRanges(of: $0, in: folded).isEmpty }
    }

    /// Where `word` stands in `text` as a whole word: no letter or digit right before it, and none
    /// right after it unless the word ends in punctuation ("due:"). A word ending in `*` is a stem
    /// and matches anywhere, inside compounds too ("rechnung*" in "Stromrechnung"). `text` and
    /// `word` are compared as given, so fold or lowercase both first.
    static func wordRanges(of word: String, in text: NSString) -> [NSRange] {
        if word.hasSuffix("*") {
            let stem = String(word.dropLast())
            var ranges: [NSRange] = []
            var search = NSRange(location: 0, length: text.length)
            while true {
                let found = text.range(of: stem, options: [], range: search)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                let end = found.location + found.length
                search = NSRange(location: end, length: text.length - end)
            }
            return ranges
        }
        var ranges: [NSRange] = []
        var search = NSRange(location: 0, length: text.length)
        let checksEnd = word.last.map { $0.isLetter || $0.isNumber } ?? false
        while true {
            let found = text.range(of: word, options: [], range: search)
            guard found.location != NSNotFound else { break }
            let end = found.location + found.length
            let startsWord = found.location == 0 || !isWordCharacter(text.character(at: found.location - 1))
            let endsWord = !checksEnd || end >= text.length || !isWordCharacter(text.character(at: end))
            if startsWord && endsWord { ranges.append(found) }
            search = NSRange(location: end, length: text.length - end)
        }
        return ranges
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func containsWord(_ word: String, in folded: String) -> Bool {
        !wordRanges(of: word, in: folded as NSString).isEmpty
    }

    /// The facts for one document, most useful first.
    ///
    /// - Parameters:
    ///   - pageCount: Pages or slides, from the file or Spotlight.
    ///   - isPresentation: Count slides instead of pages.
    static func facts(text: String, name: String, pageCount: Int?, isPresentation: Bool) -> [FlixFactValue] {
        var facts: [FlixFactValue] = []
        let folded = fold(text)
        if let due = date(after: dueWords, in: text) { facts.append(.due(due)) }
        if let valid = date(after: validWords, in: text) { facts.append(.validUntil(valid)) }
        let financial = looksFinancial(folded, name: name)
        if financial, let total = total(in: text) {
            facts.append(.amount(total.value, currency: total.currency))
        }
        let foldedName = fold(name)
        if signedNameWords.contains(where: { containsWord($0, in: foldedName) })
            || signedWords.contains(where: { containsWord($0, in: folded) }) {
            facts.append(.signed)
        } else if signatureWords.contains(where: { containsWord($0, in: folded) }) {
            facts.append(.needsSignature)
        } else if paidWords.contains(where: { containsWord($0, in: folded) }) {
            facts.append(.paid)
        } else if financial, autoDebitWords.contains(where: { containsWord($0, in: folded) }),
                  !statementWords.contains(where: { containsWord($0, in: folded) }) {
            // A bill collected by direct debit; a bank statement lists debits without being one.
            facts.append(.autoDebit)
        }
        if let pageCount, pageCount > 1 { facts.append(isPresentation ? .slides(pageCount) : .pages(pageCount)) }
        return Array(facts.prefix(limit))
    }

    // MARK: Amounts

    private static let currencyPattern = #"(?:€|\$|£|EUR|USD|GBP|CHF|Euro)"#
    private static let numberPattern = #"(?:\d{1,3}(?:[.,' ]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let prefixed = try! NSRegularExpression(pattern: "(\(currencyPattern))\\s?(\(numberPattern))")
    private static let suffixed = try! NSRegularExpression(pattern: "(\(numberPattern))\\s?(\(currencyPattern))(?![A-Za-z])")
    private static let totalWords = ["total", "gesamt*", "summe", "endsumme*", "amount due", "balance due", "betrag*",
                                     "zu zahlen", "grand total"]
    private static let financialWords = ["invoice", "rechnung*", "receipt", "quittung*", "quote", "angebot*", "bill",
                                         "beleg", "order", "bestellung*", "payment", "zahlung*", "kostenvoranschlag*",
                                         "estimate", "statement"]

    /// Every money amount in `text` with its ISO currency code and where it sits.
    static func amounts(in text: String) -> [(value: Double, currency: String, location: Int)] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [(Double, String, Int)] = []
        for match in prefixed.matches(in: text, range: range) {
            guard let symbol = Range(match.range(at: 1), in: text), let number = Range(match.range(at: 2), in: text),
                  let value = parseNumber(String(text[number])) else { continue }
            found.append((value, currencyCode(String(text[symbol])), match.range.location))
        }
        for match in suffixed.matches(in: text, range: range) {
            guard let number = Range(match.range(at: 1), in: text), let symbol = Range(match.range(at: 2), in: text),
                  let value = parseNumber(String(text[number])) else { continue }
            found.append((value, currencyCode(String(text[symbol])), match.range.location))
        }
        return found.filter { $0.0 > 0 }.sorted { $0.2 < $1.2 }.map { (value: $0.0, currency: $0.1, location: $0.2) }
    }

    /// The document's total: the largest amount shortly after a word like "Total" or "Gesamt",
    /// else the largest amount.
    static func total(in text: String) -> (value: Double, currency: String)? {
        let amounts = amounts(in: text)
        guard !amounts.isEmpty else { return nil }
        let lowered = text.lowercased() as NSString
        var nearTotal: [(value: Double, currency: String, location: Int)] = []
        for word in totalWords {
            for found in wordRanges(of: word, in: lowered) {
                let end = found.location + found.length
                nearTotal += amounts.filter { $0.location >= end && $0.location - end <= 60 }
            }
        }
        let best = (nearTotal.isEmpty ? amounts : nearTotal).max { $0.value < $1.value }
        return best.map { (value: $0.value, currency: $0.currency) }
    }

    /// "1,240.50", "1.240,50", "3 980", "1'240" and "12,5" as numbers. A separator followed by
    /// exactly three digits groups thousands; one followed by one or two digits is the decimal mark.
    /// The text is untrusted (OCR, file contents, typed queries), so a value that is not finite or
    /// exceeds ``FlixNumbers/maximumAmount`` is nil rather than infinity.
    static func parseNumber(_ raw: String) -> Double? {
        let compact = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        let parsed: Double?
        if let last = compact.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = compact[compact.index(after: last)...]
            let head = compact[..<last].filter(\.isNumber)
            parsed = tail.count == 3 ? Double(head + tail) : Double(head + "." + tail)
        } else {
            parsed = Double(compact)
        }
        return FlixNumbers.finite(parsed, in: 0...FlixNumbers.maximumAmount)
    }

    private static func currencyCode(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "€", "EUR", "EURO": "EUR"
        case "$", "USD": "USD"
        case "£", "GBP": "GBP"
        default: symbol.uppercased()
        }
    }

    private static func looksFinancial(_ folded: String, name: String) -> Bool {
        let foldedName = fold(name)
        return financialWords.contains { containsWord($0, in: folded) || containsWord($0, in: foldedName) }
            || totalWords.contains { containsWord($0, in: folded) }
    }

    // MARK: Dates

    private static let dueWords = ["payment due", "due date", "due on", "due by", "pay by", "payable by", "due:",
                                   "fallig am*", "fallig bis*", "fallig:*", "falligkeitsdatum*", "falligkeit*", "fallig*",
                                   "zahlbar bis*", "zahlungsziel*", "zahlen sie bis*", "due"]
    private static let validWords = ["valid until", "valid till", "valid through", "expires on", "expires",
                                     "gultig bis*", "gultigkeit bis*", "befristet bis*"]
    private static let signatureWords = ["please sign", "sign here", "signature required", "requires your signature",
                                         "awaiting signature", "for your signature", "bitte unterschreiben*",
                                         "unterschrift erforderlich*", "zur unterschrift*", "bitte unterzeichnen*",
                                         "bitte unterschrieben zuruck*"]
    /// In the text, only phrases that report a signature already made: "to be signed" or "bitte
    /// unterschrieben zurück" ask for one.
    private static let signedWords = ["signed by", "electronically signed", "digitally signed", "unterzeichnet von*",
                                      "signiert von*", "elektronisch signiert*"]
    /// In a file name, the word alone is enough: "Signed contract.pdf", "Vertrag_unterschrieben.pdf".
    private static let signedNameWords = ["signed", "unterschrieben*", "signiert*"]
    /// Wording of a bill whose amount is collected automatically ("SEPA-Lastschriftmandat",
    /// "wird von Ihrem Konto abgebucht", "paid by direct debit").
    private static let autoDebitWords = ["direct debit", "will be debited", "debited from your account", "lastschrift*",
                                         "abgebucht*", "abbuchung*"]
    private static let statementWords = ["kontoauszug*", "account statement", "bank statement", "kreditkartenabrechnung*",
                                         "card statement"]
    private static let paidWords = ["paid in full", "payment received", "status: paid", "already paid", "bereits bezahlt*",
                                    "zahlung erhalten*", "betrag erhalten*"]

    private static let months: [String: Int] = [
        "january": 1, "jan": 1, "januar": 1, "february": 2, "feb": 2, "februar": 2, "march": 3, "mar": 3, "marz": 3,
        "maerz": 3, "april": 4, "apr": 4, "may": 5, "mai": 5, "june": 6, "jun": 6, "juni": 6, "july": 7, "jul": 7,
        "juli": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "oktober": 10,
        "okt": 10, "november": 11, "nov": 11, "december": 12, "dec": 12, "dezember": 12, "dez": 12,
    ]
    private static let monthPattern = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let datePatterns: [(NSRegularExpression, (day: Int, month: Int, year: Int))] = [
        (try! NSRegularExpression(pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#), (3, 2, 1)),
        (try! NSRegularExpression(pattern: #"\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})\b"#), (1, 2, 3)),
        (try! NSRegularExpression(pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\.?\\s+(\(monthPattern))\\.?,?\\s+(\\d{4})\\b",
                                  options: .caseInsensitive), (1, 2, 3)),
        (try! NSRegularExpression(pattern: "\\b(\(monthPattern))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b",
                                  options: .caseInsensitive), (2, 1, 3)),
    ]

    /// Every date written out in `text`, with where it starts in the folded text.
    static func dates(in text: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> [(date: Date, location: Int)] {
        let folded = fold(text)
        let range = NSRange(folded.startIndex..., in: folded)
        var found: [(Date, Int)] = []
        for (pattern, order) in datePatterns {
            for match in pattern.matches(in: folded, range: range) {
                func part(_ index: Int) -> String? {
                    Range(match.range(at: index), in: folded).map { String(folded[$0]) }
                }
                guard let dayText = part(order.day), let monthText = part(order.month), let yearText = part(order.year),
                      let day = Int(dayText), var year = Int(yearText),
                      let month = Int(monthText) ?? months[monthText.lowercased()] else { continue }
                if year < 100 { year += 2000 }
                guard (1...12).contains(month), (1...31).contains(day), (1990...2100).contains(year),
                      let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                      calendar.component(.day, from: date) == day else { continue }
                found.append((date, match.range.location))
            }
        }
        return found.sorted { $0.1 < $1.1 }.map { (date: $0.0, location: $0.1) }
    }

    /// Whether `text` says more than its dates: at least three letters remain once every date in it
    /// is taken out. A bare "27.10.2026" or "27. Okt. 2026" does not; "Zahlbar bis 27.10.2026" does.
    static func saysMoreThanDates(_ text: String) -> Bool {
        var rest = fold(text)
        for (pattern, _) in datePatterns {
            rest = pattern.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: " ")
        }
        return rest.filter(\.isLetter).count >= 3
    }

    /// The first date within 50 characters after one of `words`.
    static func date(after words: [String], in text: String) -> Date? {
        let folded = fold(text) as NSString
        let dates = dates(in: text)
        guard !dates.isEmpty else { return nil }
        for word in words {
            for found in wordRanges(of: word, in: folded) {
                let end = found.location + found.length
                if let date = dates.first(where: { $0.location >= end && $0.location - end <= 50 }) { return date.date }
            }
        }
        return nil
    }

    /// Lowercased with diacritics folded, keeping every character's position comparable.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
