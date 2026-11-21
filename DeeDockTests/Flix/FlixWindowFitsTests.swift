import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// Reading a window's demand without Apple Intelligence, and matching it against the history.
struct FlixWindowFitsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, kind: FlixItemKind = .document, type: UTType? = .pdf, age: TimeInterval = 3_600,
                      bytes: Int64? = 200_000) -> FlixItem {
        FlixItem(path: "/Users/x/Downloads/" + name, name: name, kind: kind, activity: .downloaded,
                 date: now.addingTimeInterval(-age), contentTypeIdentifier: type?.identifier, byteSize: bytes)
    }

    // MARK: Fallback parsing

    @Test func portalTextGivesItemsTypesAndSize() {
        let text = """
        Upload documents
        Attach the signed contract and this month's invoice.
        PDF only · max 5 MB per file
        Drop files here
        """
        let demand = FlixDemandFallbackParser.parse(text)
        #expect(demand.wanted.map(\.phrase) == ["the signed contract", "this month's invoice"])
        #expect(demand.wanted.first?.keywords == ["signed", "contract"])
        #expect(demand.acceptedTypes == [.pdf])
        #expect(demand.maximumBytes == 5_000_000)
        #expect(demand.pageKind == .upload)
    }

    @Test func mailDraftKeepsTheAppsKind() {
        let text = "Hi Mike,\nattaching the moodboard and the packaging quote. Spec follows once you're happy."
        let demand = FlixDemandFallbackParser.parse(text, pageKind: .mail)
        #expect(demand.wanted.map(\.phrase) == ["the moodboard", "the packaging quote"])
        #expect(demand.pageKind == .mail)
        #expect(!demand.hasLimits)
    }

    @Test func chatRequestDropsTheAddressee() {
        let demand = FlixDemandFallbackParser.parse("Can you send me that build error screenshot?", pageKind: .chat)
        #expect(demand.wanted.map(\.phrase) == ["that build error screenshot"])
        #expect(demand.wanted.first?.keywords == ["build", "error", "screenshot"])
    }

    @Test func germanRequestsAreUnderstood() {
        let demand = FlixDemandFallbackParser.parse("Bitte den Mietvertrag hochladen. Nur PDF, höchstens 2 MB.")
        #expect(demand.wanted.map(\.phrase) == ["den Mietvertrag"])
        #expect(demand.wanted.first?.keywords == ["mietvertrag"])
        #expect(demand.acceptedTypes == [.pdf])
        #expect(demand.maximumBytes == 2_000_000)
        #expect(demand.pageKind == .upload)
    }

    @Test(arguments: [("Files up to 10 MB", Int64(10_000_000)), ("Maximum file size: 2.5 MB", 2_500_000),
                      ("500 KB max", 500_000), ("bis zu 1,5 GB", 1_500_000_000), ("Uploaded 3 MB of 9 MB", nil)])
    func sizeLimitsAreRead(line: String, bytes: Int64?) {
        #expect(FlixDemandFallbackParser.sizeLimit(in: line.lowercased()) == bytes)
    }

    @Test func typeWordsNeedALimitWord() {
        #expect(FlixDemandFallbackParser.parse("Your PDF and PNG exports are ready").acceptedTypes.isEmpty)
        #expect(FlixDemandFallbackParser.parse("Accepted formats: JPG, PNG, HEIC").acceptedTypes == [.jpeg, .png, .heic])
    }

    @Test func textPolicyNeedsAboutASentence() {
        #expect(!FlixWindowTextPolicy.isEnough("Back Forward Reload"))
        #expect(FlixWindowTextPolicy.isEnough("Upload documents. Attach the signed contract and this month's invoice."))
    }

    // MARK: Scoring and ranking

    @Test func bestMatchPerPhraseComesFirst() {
        let demand = FlixDemandFallbackParser.parse("Attach the signed contract and this month's invoice. PDF only.")
        let signed = item("Contract_signed.pdf")
        let draft = item("Contract_draft.pdf", age: 60)
        let invoice = item("Invoice-November.pdf", age: 7_200)
        let photo = item("Holiday.jpg", kind: .image, type: .jpeg)
        let ranked = FlixFitRanker.rank(demand: demand,
                                        candidates: [draft, photo, signed, invoice].map { FlixFitCandidate(item: $0) },
                                        scorer: FlixKeywordFitScorer(), now: now)
        #expect(ranked.first?.itemID == signed.id)
        #expect(ranked.first?.phrase == "the signed contract")
        #expect(ranked.contains { $0.itemID == invoice.id && $0.phrase == "this month's invoice" })
        #expect(ranked.count <= FlixFitRanker.maximumFits)
        #expect(!ranked.contains { $0.itemID == photo.id })
    }

    @Test func synonymsAndCaptionsMatch() {
        let wanted = FlixWindowDemand.Wanted(phrase: "the agreement", keywords: ["agreement"])
        let scorer = FlixKeywordFitScorer()
        #expect(scorer.score(wanted, item: FlixFitCandidate(item: item("Holiday.pdf")), now: now) == 0)
        // "Vertrag" is a synonym, and German compounds end with it.
        #expect(scorer.score(wanted, item: FlixFitCandidate(item: item("Mietvertrag.pdf")), now: now) >= FlixFitRanker.minimumScore)
        #expect(scorer.score(wanted, item: FlixFitCandidate(item: item("NDA Acme.pdf")), now: now) >= FlixFitRanker.minimumScore)
        let captioned = FlixFitCandidate(item: item("scan-0042.pdf"), caption: "Signed agreement with Oak & Ash")
        #expect(scorer.score(wanted, item: captioned, now: now) >= FlixFitRanker.minimumScore)
    }

    @Test func aKindWordAloneDoesNotMatchAnyPicture() {
        let wanted = FlixWindowDemand.Wanted(phrase: "the moodboard photo", keywords: ["moodboard", "photo"])
        let photo = FlixFitCandidate(item: item("IMG_2041.jpg", kind: .image, type: .jpeg))
        #expect(FlixKeywordFitScorer().score(wanted, item: photo, now: now) == 0)
        let screenshot = FlixWindowDemand.Wanted(phrase: "that screenshot", keywords: ["screenshot"])
        let shot = FlixFitCandidate(item: item("Screen Shot 2026.png", kind: .screenshot, type: .png))
        #expect(FlixKeywordFitScorer().score(screenshot, item: shot, now: now) > 0)
    }

    @Test func uploadPagesSkipFoldersAndUnconvertibleFiles() {
        var demand = FlixWindowDemand(wanted: [.init(phrase: "the report", keywords: ["report"])], acceptedTypes: [.pdf],
                                      pageKind: .upload)
        let folder = FlixItem(path: "/Users/x/Report", name: "Report", kind: .folder, activity: .opened, date: now)
        let pages = item("Report.pages", type: UTType("com.apple.iwork.pages.sec"))
        let rtf = item("Report.rtf", type: .rtf)
        let ranked = FlixFitRanker.rank(demand: demand, candidates: [folder, pages, rtf].map { FlixFitCandidate(item: $0) },
                                        scorer: FlixKeywordFitScorer(), now: now)
        #expect(ranked.map(\.itemID) == [rtf.id])
        demand.acceptedTypes = []
        #expect(FlixFitRanker.isUsable(pages, for: demand))
    }
}
