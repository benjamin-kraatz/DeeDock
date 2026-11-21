import Foundation
import Testing
@testable import DeeDock

/// Key facts read without a model (English and German), and AI observability's per-call content
/// opt-out that every Flix Files model call uses.
extension FlixGeneratedDocument {
    /// A reading with only the given facts; everything else empty.
    static func reading(kind: FlixGeneratedDocumentKind = .invoice, due: (String, String)? = nil,
                        validUntil: (String, String)? = nil,
                        total: (Double, String)? = nil, payment: FlixGeneratedPayment = .none,
                        paymentEvidence: String? = nil, signature: FlixGeneratedSignature = .none,
                        signatureEvidence: String? = nil) -> FlixGeneratedDocument {
        FlixGeneratedDocument(caption: "", fileName: "", kind: kind, payment: payment, paymentEvidence: paymentEvidence,
                              dueDate: due?.0, dueDateEvidence: due?.1, validUntil: validUntil?.0, validUntilEvidence: validUntil?.1,
                              total: total?.0, totalEvidence: total?.1, signature: signature,
                              signatureEvidence: signatureEvidence)
    }
}

struct FlixFactsAndPrivacyTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func englishInvoiceGivesDueDateTotalAndPages() {
        let text = "Invoice No. 2026-11\nHosting, November\nTotal: €1,240.00\nPayment due: Dec 4, 2026"
        let facts = FlixFactExtractor.facts(text: text, name: "Invoice-2026-11.pdf", pageCount: 2, isPresentation: false)
        #expect(facts == [.due(day(2026, 12, 4)), .amount(1_240, currency: "EUR"), .pages(2)])
    }

    @Test func germanInvoiceGivesDueDateAndTotal() {
        let text = "Rechnung Nr. 4711\nGesamtbetrag: 3.980,00 €\nZahlbar bis 15.12.2026"
        let facts = FlixFactExtractor.facts(text: text, name: "scan.pdf", pageCount: nil, isPresentation: false)
        #expect(facts == [.due(day(2026, 12, 15)), .amount(3_980, currency: "EUR")])
        let debit = "Rechnung\nZu zahlender Betrag 14,90 EUR\nGemäß Ihrem SEPA-Lastschriftmandat buchen wir den Betrag ab."
        #expect(FlixFactExtractor.facts(text: debit, name: "scan.pdf", pageCount: 3, isPresentation: false)
                == [.amount(14.9, currency: "EUR"), .autoDebit, .pages(3)])
    }

    @Test func signaturesAndCountsFromMetadata() {
        #expect(FlixFactExtractor.facts(text: "Please sign and return the agreement.", name: "Contract draft v3.docx",
                                        pageCount: nil, isPresentation: false) == [.needsSignature])
        #expect(FlixFactExtractor.facts(text: "", name: "Signed contract.pdf", pageCount: 6, isPresentation: false)
                == [.signed, .pages(6)])
        #expect(FlixFactExtractor.facts(text: "", name: "Launch deck.key", pageCount: 31, isPresentation: true) == [.slides(31)])
        // Amounts in a text that isn't about money are not facts.
        #expect(FlixFactExtractor.facts(text: "The fund raised $40 million.", name: "Article.pdf", pageCount: nil,
                                        isPresentation: false).isEmpty)
    }

    @Test(arguments: [("1,240.50", 1_240.5), ("1.240,50", 1_240.5), ("3 980", 3_980.0), ("12,5", 12.5), ("1'240", 1_240.0)])
    func numbersInEitherNotation(_ text: String, _ value: Double) {
        #expect(FlixFactExtractor.parseNumber(text) == value)
    }

    @Test func modelFactsNeedTheTextToBackThem() {
        let document = FlixGeneratedDocument.reading(due: ("2026-12-15", "Payment due 15 Dec 2026"), total: (9_999, "Total €9,999"),
                                                     signature: .needed, signatureEvidence: "Please sign")
        let facts = FlixDocumentReading.facts(from: document, text: "Quote for packaging, 3 options",
                                              pageCount: 3, isPresentation: false)
        // None of the evidence is in the text.
        #expect(facts == [.pages(3)])
    }

    /// A direct-debit invoice (seen on an IONOS bill): the model offered its own date as the due
    /// date, the contract term as "valid until", and "signed". Only the total and Auto-debit stay.
    @Test func aDirectDebitInvoiceShowsNoDueDateValidityOrSignature() {
        let text = """
            Rechnung 27.10.2026
            Vertragslaufzeit 31.01.2025 bis zum 30.01.2027
            Zu zahlender Betrag 14,90 EUR
            Entsprechend Ihrem SEPA-Lastschriftmandat buchen wir den Rechnungsbetrag von Ihrem Konto ab.
            """
        let document = FlixGeneratedDocument.reading(
            due: ("2026-10-27", "27.10.2026"), validUntil: ("2027-01-30", "31.01.2025 bis zum 30.01.2027"),
            total: (14.9, "Zu zahlender Betrag 14,90 EUR"), payment: .directDebit,
            paymentEvidence: "SEPA-Lastschriftmandat buchen wir den Rechnungsbetrag", signature: .signed,
            signatureEvidence: "Rechnung 27.10.2026")
        let facts = FlixDocumentReading.facts(from: document, text: text, pageCount: nil, isPresentation: false)
        #expect(facts == [.amount(14.9, currency: "EUR"), .autoDebit])
    }

    /// A data file's timestamp and counts are never a due date and a total (seen on a manifest.json).
    @Test func numbersAndTimestampsInDataAreNotFacts() {
        let manifest = #"{"format": 2, "platform": "mac", "modified": "2026-11-21T09:12:00Z", "totalSize": 16581}"#
        let document = FlixGeneratedDocument.reading(due: ("2026-11-21", "2026-11-21T09:12:00Z"), total: (16_581, "16581"))
        // The evidence is in the text, but writes no date the patterns read and no currency.
        #expect(FlixDocumentReading.facts(from: document, text: manifest, pageCount: nil, isPresentation: false).isEmpty)
        #expect(!FlixFactExtractor.readsFacts(contentType: "public.json", name: "manifest.json"))
        #expect(FlixFactExtractor.readsFacts(contentType: "com.adobe.pdf", name: "Invoice.pdf"))
    }

    /// Cloud calls cost money: only expensive tasks the person asks for may ever leave the Mac.
    @Test func onlyOnDemandExpensiveTasksMayUseTheCloud() {
        let cloud = FlixAITask.allCases.filter { FlixAIRouting.engine(for: $0, cloudChosen: true) == .claude }
        #expect(cloud == [.askRobi])
        #expect(FlixAITask.allCases.allSatisfy { FlixAIRouting.engine(for: $0) == .appleIntelligence })
    }

    // MARK: AI observability

    @Test func contentOptOutKeepsOnlyMetadata() {
        let trace = AIObservability.makeTrace()
        let withheld = AIObservability.properties(trace: trace, name: "flix_caption_document", input: "the file's text",
                                                  output: "a caption", startedAt: .now, maximumResponseTokens: 200,
                                                  instructions: "describe it", includesContent: false)
        #expect(withheld["$ai_input"] == nil)
        #expect(withheld["$ai_output_choices"] == nil)
        #expect(withheld["$ai_span_name"] as? String == "flix_caption_document")
        #expect(withheld["$ai_max_tokens"] as? Int == 200)

        let shared = AIObservability.properties(trace: trace, name: "robi_answer", input: "question", output: "answer",
                                                startedAt: .now)
        #expect(shared["$ai_input"] != nil)
        #expect(shared["$ai_output_choices"] != nil)
    }
}
