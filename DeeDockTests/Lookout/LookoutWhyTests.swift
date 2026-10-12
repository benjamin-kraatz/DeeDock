import Testing
@testable import DeeDock

/// The preview's "Why it matched" sentence follows the match, the kind and the page.
struct LookoutWhyTests {
    private func why(_ hit: LookoutHit, lookup: Bool = false) -> LookoutWhy { LookoutWhy(hit: hit, isLookup: lookup) }

    @Test("A PDF page names the page with what matched")
    func pages() {
        let page = { (match: LookoutHit.Match) in
            LookoutUIFixtures.hit("/a.pdf", kind: .pdf, match: match, segment: .page, loc: 7)
        }
        #expect(why(page(.meaning)).sentence == .pageMeaning(7))
        #expect(why(page(.words)).sentence == .pageWords(7))
        #expect(why(page(.both)).sentence == .pageBoth(7))
        let scan = LookoutUIFixtures.hit("/scan.pdf", kind: .pdf, segment: .pageImage, loc: 3)
        #expect(why(scan).sentence == .pageMeaning(3))
    }

    @Test("Pictures and screenshots matched what was described; their text matched the words")
    func pictures() {
        #expect(why(LookoutUIFixtures.hit("/a.heic", kind: .image, segment: .image)).sentence == .pictureMeaning)
        #expect(why(LookoutUIFixtures.hit("/a.heic", kind: .image, match: .both, segment: .image)).sentence == .pictureBoth)
        #expect(why(LookoutUIFixtures.hit("/s.png", kind: .screenshot, segment: .image)).sentence == .screenshotMeaning)
        #expect(why(LookoutUIFixtures.hit("/s.png", kind: .screenshot, match: .words, segment: .ocr)).sentence == .words)
        #expect(why(LookoutUIFixtures.hit("/s.png", kind: .screenshot, match: .both, segment: .ocr)).sentence == .screenshotBoth)
    }

    @Test("Documents, and PDFs without a page, speak of a passage")
    func passages() {
        #expect(why(LookoutUIFixtures.hit("/a.md")).sentence == .passageMeaning)
        #expect(why(LookoutUIFixtures.hit("/a.md", match: .both)).sentence == .passageBoth)
        #expect(why(LookoutUIFixtures.hit("/a.md", match: .words)).sentence == .words)
        #expect(why(LookoutUIFixtures.hit("/a.pdf", kind: .pdf, segment: .name)).sentence == .passageMeaning)
    }

    @Test("A folder counts the files inside that match")
    func folder() {
        #expect(why(LookoutUIFixtures.hit("/Taxes", folderFiles: 6)).sentence == .folder(matchingFiles: 6))
        #expect(!why(LookoutUIFixtures.hit("/Taxes", match: .words, folderFiles: 6), lookup: true).explainsLookup)
    }

    @Test("A lookup explains why words counted double, unless only meaning matched")
    func lookup() {
        let code = LookoutUIFixtures.hit("/invoice.pdf", kind: .pdf, match: .words, segment: .page, loc: 1)
        #expect(why(code, lookup: true).explainsLookup)
        #expect(!why(code, lookup: false).explainsLookup)
        #expect(!why(LookoutUIFixtures.hit("/a.heic", kind: .image, segment: .image), lookup: true).explainsLookup)
        #expect(why(code, lookup: true).text.count > why(code, lookup: false).text.count)
    }

    @Test("The kind chip shows the page for a PDF page")
    func kindChip() {
        #expect(LookoutHitKind(LookoutUIFixtures.hit("/a.pdf", kind: .pdf, segment: .page, loc: 7)) == .pdf(page: 7))
        #expect(LookoutHitKind(LookoutUIFixtures.hit("/a.pdf", kind: .pdf, segment: .chunk, loc: 2)) == .pdf(page: nil))
        #expect(LookoutHitKind(LookoutUIFixtures.hit("/F", folderFiles: 3)) == .folder(matchingFiles: 3))
        #expect(LookoutHitKind(LookoutUIFixtures.hit("/s.png", kind: .screenshot)) == .screenshot)
    }
}
