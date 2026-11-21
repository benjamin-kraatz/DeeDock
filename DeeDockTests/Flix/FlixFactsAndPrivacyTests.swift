import Foundation
import Testing
@testable import DeeDock

/// Key facts read without a model (English and German), and AI observability's per-call content
/// opt-out that every Flix Files model call uses.
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
        let document = FlixGeneratedDocument(caption: "Quote", fileName: "Quote", dueDate: "2026-12-15", total: 9_999,
                                             currency: "EUR", needsSignature: true, isSigned: false)
        let merged = FlixFileAnalyzer.merge([.pages(3)], with: document, text: "Quote for packaging, 3 options",
                                            pageCount: 3, isPresentation: false)
        // The text names no due date, shows no total, and mentions no signature.
        #expect(merged == [.pages(3)])
    }

    /// A data file's timestamp and counts are never a due date and a total (seen on a manifest.json).
    @Test func numbersAndTimestampsInDataAreNotFacts() {
        let manifest = #"{"format": 2, "platform": "mac", "modified": "2026-11-21T09:12:00Z", "totalSize": 16581}"#
        let document = FlixGeneratedDocument(caption: "Manifest", fileName: "Manifest", dueDate: "2026-11-21", total: 16_581,
                                             currency: "", needsSignature: false, isSigned: false)
        #expect(FlixFileAnalyzer.merge([], with: document, text: manifest, pageCount: nil, isPresentation: false).isEmpty)
        #expect(!FlixFactExtractor.readsFacts(contentType: "public.json", name: "manifest.json"))
        #expect(FlixFactExtractor.readsFacts(contentType: "com.adobe.pdf", name: "Invoice.pdf"))
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
