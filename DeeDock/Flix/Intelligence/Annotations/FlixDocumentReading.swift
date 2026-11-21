import Foundation
import FoundationModels

@Generable(description: "What a document is and its key facts, read from its text. Every fact needs the exact words it was read from.")
nonisolated struct FlixGeneratedDocument {
    @Guide(description: "One line under 70 characters naming what the document is and who or what it is for, such as \"Oak & Ash packaging quote, 3 options\". No file name, no \"This document\".")
    var caption: String
    @Guide(description: "A short descriptive file name of two to six words, without an extension, such as \"Oak & Ash – Packaging quote\".")
    var fileName: String
    @Guide(description: "What kind of document this is.")
    var kind: FlixGeneratedDocumentKind
    @Guide(description: "Whether money is owed and how it is settled. directDebit when the text says the amount is collected from an account or card; alreadyPaid when it says it is paid; open when it asks to be paid; none when it is not about a payment.")
    var payment: FlixGeneratedPayment
    @Guide(description: "The exact words from the text that show the payment state, copied verbatim; empty when payment is none.")
    var paymentEvidence: String?
    @Guide(description: "The date by which to pay as yyyy-MM-dd, only when the text names one. Never the document's own date.")
    var dueDate: String?
    @Guide(description: "The exact words from the text that state the due date, copied verbatim, including the date.")
    var dueDateEvidence: String?
    @Guide(description: "The date an offer or document stays valid until as yyyy-MM-dd, only when the text names one.")
    var validUntil: String?
    @Guide(description: "The exact words from the text that state the valid-until date, copied verbatim, including the date.")
    var validUntilEvidence: String?
    @Guide(description: "The final amount to pay, or the quoted total, only when the text states one.")
    var total: Double?
    @Guide(description: "The exact words from the text that state the total with its currency, copied verbatim, such as \"Gesamtbetrag 3.980,00 €\".")
    var totalEvidence: String?
    @Guide(description: "needed when the text asks the reader to sign; signed when it shows a signature was made; none otherwise.")
    var signature: FlixGeneratedSignature
    @Guide(description: "The exact words from the text that show the signature state, copied verbatim; empty when signature is none.")
    var signatureEvidence: String?
}

@Generable
nonisolated enum FlixGeneratedDocumentKind {
    case invoice, receipt, quote, paymentReminder, contract, bankStatement, cardStatement, payslip, taxDocument
    /// A passport, ID card, driving licence, or residence permit.
    case identityDocument
    case letter, form, other
}

@Generable
nonisolated enum FlixGeneratedPayment {
    case open, alreadyPaid, directDebit, none
}

@Generable
nonisolated enum FlixGeneratedSignature {
    case needed, signed, none
}

/// What kind of document a file is, as Apple Intelligence read it. Stored with the analysis, and
/// read by the sensitive guard to settle its text rules' verdict (`FlixSensitiveRules.verdict`).
nonisolated enum FlixDocumentKind: String, Codable, Sendable {
    case invoice, receipt, quote, paymentReminder, contract, bankStatement, cardStatement, payslip, taxDocument
    case identityDocument, letter, form, other

    init(_ generated: FlixGeneratedDocumentKind) {
        self = switch generated {
        case .invoice: .invoice
        case .receipt: .receipt
        case .quote: .quote
        case .paymentReminder: .paymentReminder
        case .contract: .contract
        case .bankStatement: .bankStatement
        case .cardStatement: .cardStatement
        case .payslip: .payslip
        case .taxDocument: .taxDocument
        case .identityDocument: .identityDocument
        case .letter: .letter
        case .form: .form
        case .other: .other
        }
    }

    /// A document that asks for, confirms, or offers a payment. It prints bank details to be paid,
    /// and is made to be passed on (to an accountant, an expense report).
    var isPaymentDocument: Bool {
        switch self {
        case .invoice, .receipt, .quote, .paymentReminder: true
        default: false
        }
    }
}

/// Turns Apple Intelligence's reading of a document into key facts, keeping only what the text
/// proves: the model decides what a document is and what matters in it, and each fact must come
/// with the words it was read from, which must appear in the text and contain the fact itself.
///
/// - A due or valid-until date: the evidence is in the text and writes that day out.
/// - A total: the evidence is in the text and shows that amount with a currency; the evidence's
///   currency wins over the model's.
/// - Paid, auto-debit, signature needed, signed: the evidence is in the text.
///
/// So a timestamp in a data file, an order number, or a date the model guessed never becomes a
/// chip. Page and slide counts come from the file, not the model, and stay last.
nonisolated enum FlixDocumentReading {
    static func facts(from document: FlixGeneratedDocument, text: String, pageCount: Int?,
                      isPresentation: Bool) -> [FlixFactValue] {
        let normalizedText = normalized(text)
        func proven(_ evidence: String?) -> String? {
            guard let evidence, normalized(evidence).count >= 4, normalizedText.contains(normalized(evidence)) else { return nil }
            return evidence
        }
        var facts: [FlixFactValue] = []
        if let due = day(document.dueDate, provenBy: proven(document.dueDateEvidence)) { facts.append(.due(due)) }
        if let valid = day(document.validUntil, provenBy: proven(document.validUntilEvidence)) {
            facts.append(.validUntil(valid))
        }
        if let total = FlixNumbers.amount(document.total), let evidence = proven(document.totalEvidence),
           let shown = FlixFactExtractor.amounts(in: evidence).first(where: { abs($0.value - total) < 0.005 }) {
            facts.append(.amount(shown.value, currency: shown.currency))
        }
        if document.signature == .signed, proven(document.signatureEvidence) != nil {
            facts.append(.signed)
        } else if document.signature == .needed, proven(document.signatureEvidence) != nil {
            facts.append(.needsSignature)
        } else if proven(document.paymentEvidence) != nil {
            switch document.payment {
            case .alreadyPaid: facts.append(.paid)
            case .directDebit: facts.append(.autoDebit)
            case .open, .none: break
            }
        }
        if let pageCount, pageCount > 1 { facts.append(isPresentation ? .slides(pageCount) : .pages(pageCount)) }
        // Counts stay last, so the chips that need attention come first.
        let counts = facts.filter { if case .pages = $0 { true } else if case .slides = $0 { true } else { false } }
        facts.removeAll { counts.contains($0) }
        return Array((facts + counts).prefix(FlixFactExtractor.limit))
    }

    /// The model's `yyyy-MM-dd` day, when its evidence writes the same day out.
    private static func day(_ iso: String?, provenBy evidence: String?) -> Date? {
        guard let iso, let evidence else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1990...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              FlixFactExtractor.dates(in: evidence, calendar: calendar).contains(where: { calendar.isDate($0.date, inSameDayAs: date) })
        else { return nil }
        return date
    }

    /// Case, accents, and runs of white space ignored, so a quote across a line break still matches.
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
