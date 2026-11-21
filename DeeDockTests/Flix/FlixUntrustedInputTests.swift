import Foundation
import Testing
@testable import DeeDock

/// Numbers from window text, OCR, and model output never trap; AI observability never carries an
/// error's own text for a call that withholds content; and switching Flix Files off stops its
/// background passes.
struct FlixUntrustedInputTests {
    // MARK: Numbers

    @Test(arguments: [Double.nan, .infinity, -.infinity, 1e300, -1e300, Double(Int64.max), -Double(Int64.max) * 4])
    func nonFiniteAndHugeValuesAreNoNumber(_ value: Double) {
        #expect(FlixNumbers.int64(value, in: Int64.min...Int64.max) == nil)
        #expect(FlixNumbers.int(value, in: 0...1_000) == nil)
        #expect(FlixNumbers.amount(value) == nil)
    }

    @Test func boundedValuesConvert() {
        #expect(FlixNumbers.int64(2.9, in: 0...10) == 2)
        #expect(FlixNumbers.int64(11, in: 0...10) == nil)
        #expect(FlixNumbers.amount(1_240.5) == 1_240.5)
        #expect(FlixNumbers.amount(0) == nil)
    }

    @Test(arguments: ["up to 99999999999999999999999999999999999 GB", "maximum \(String(repeating: "9", count: 400)) MB",
                      "up to 5000 GB"])
    func absurdSizeLimitsInWindowTextAreIgnored(line: String) {
        #expect(FlixDemandFallbackParser.sizeLimit(in: line.lowercased()) == nil)
    }

    @Test func absurdAmountsInTextAreNoNumber() {
        #expect(FlixFactExtractor.parseNumber(String(repeating: "9", count: 400)) == nil)
        #expect(FlixFactExtractor.parseNumber("1,240.50") == 1_240.5)
    }

    @Test func modelTotalsThatAreNotFiniteAreDropped() {
        let document = FlixGeneratedDocument.reading(total: (.infinity, "Total €999"))
        #expect(FlixDocumentReading.facts(from: document, text: "Total €999", pageCount: nil, isPresentation: false).isEmpty)
    }

    // MARK: AI observability

    @Test func withheldContentWithholdsErrorTextToo() {
        let trace = AIObservability.makeTrace()
        let leaky = "Server said: forbidden for user@example.com at api.internal.example"
        let withheld = AIObservability.properties(trace: trace, name: "flix_ask_robi", input: "", startedAt: .now,
                                                  error: leaky, includesContent: false)
        #expect(withheld["$ai_error"] as? String == AIObservability.ErrorCode.other.rawValue)
        #expect(withheld["$ai_is_error"] as? Bool == true)
        let coded = AIObservability.properties(trace: trace, name: "flix_ask_robi", input: "", startedAt: .now,
                                               errorCode: .rateLimited, includesContent: false)
        #expect(coded["$ai_error"] as? String == "rate_limited")
        // A caller that shares content still sends its (redacted) message.
        let shared = AIObservability.properties(trace: trace, name: "robi_answer", input: "q", startedAt: .now, error: "Too long")
        #expect(shared["$ai_error"] as? String == "Too long")
    }

    @Test func errorsMapToClosedCodes() {
        #expect(AIObservability.ErrorCode(URLError(.notConnectedToInternet)) == .offline)
        #expect(AIObservability.ErrorCode(URLError(.timedOut)) == .timeout)
        #expect(AIObservability.ErrorCode(URLError(.cannotFindHost)) == .network)
        #expect(AIObservability.ErrorCode(CocoaError(.fileReadUnknown)) == .other)
    }

    // MARK: Master switch

    @MainActor private final class CountingAnnotations: FlixAnnotationProviding {
        var calls = 0
        func annotations(for items: [FlixItem], known: [FlixItem.ID: FlixItemAnnotation]) async
            -> [FlixItem.ID: FlixItemAnnotation] {
            calls += 1
            return [:]
        }
    }

    @MainActor @Test func switchingFlixOffStopsAndBlocksBackgroundPasses() {
        let intelligence = FlixIntelligence()
        var providers = FlixIntelligenceProviders()
        providers.annotations = CountingAnnotations()
        intelligence.providers = providers
        let item = FlixItem(path: "/tmp/a.pdf", name: "a.pdf", kind: .document, activity: .opened, date: .now)

        intelligence.historyChanged(items: [item])
        #expect(intelligence.isBackgroundPassPending)

        var off = FlixSettings()
        off.isEnabled = false
        intelligence.settings = off
        #expect(!intelligence.isBackgroundPassPending)
        intelligence.historyChanged(items: [item])
        #expect(!intelligence.isBackgroundPassPending)
    }
}
