import Testing
@testable import DeeDock

/// Lookout snippets mark the query's words « like this »: the markers become highlighted runs and never show.
struct LookoutSnippetTests {
    private typealias Run = LookoutSnippet.Run

    @Test("Marked words become highlighted runs without the markers")
    func marked() {
        let snippet = LookoutSnippet(marked: "…your card was «declined» at «checkout» today…")
        #expect(snippet.runs == [Run(text: "…your card was ", isMatch: false), Run(text: "declined", isMatch: true),
                                 Run(text: " at ", isMatch: false), Run(text: "checkout", isMatch: true),
                                 Run(text: " today…", isMatch: false)])
        #expect(snippet.text == "…your card was declined at checkout today…")
        #expect(!snippet.text.contains("«") && !snippet.text.contains("»"))
    }

    @Test("Neighbouring marks merge into one highlight")
    func adjacent() {
        let snippet = LookoutSnippet(marked: "«Payment»«declined»!")
        #expect(snippet.runs == [Run(text: "Paymentdeclined", isMatch: true), Run(text: "!", isMatch: false)])
    }

    @Test("A stray closing mark is dropped, an unclosed one highlights to the end, and empty marks vanish")
    func unbalanced() {
        #expect(LookoutSnippet(marked: "a » b").runs == [Run(text: "a  b", isMatch: false)])
        #expect(LookoutSnippet(marked: "a «b c").runs == [Run(text: "a ", isMatch: false), Run(text: "b c", isMatch: true)])
        #expect(LookoutSnippet(marked: "a «» b").runs == [Run(text: "a  b", isMatch: false)])
        #expect(LookoutSnippet(marked: "«a «b» c").text == "a b c")
    }

    @Test("Text without marks is one plain run")
    func plain() {
        let snippet = LookoutSnippet(marked: "Tiere sind im Treppenhaus an der Leine zu führen.")
        #expect(snippet.runs.count == 1 && !snippet.hasMatches)
    }

    @Test("An excerpt highlights the query's terms as keyword search finds them")
    func excerptTerms() {
        let snippet = LookoutSnippet(text: "Ask whether the Cat counts under the pet clause", terms: ["cat", "pet"])
        #expect(snippet.runs.filter(\.isMatch).map(\.text) == ["Cat", "pet"])
        #expect(snippet.text == "Ask whether the Cat counts under the pet clause")
    }

    @Test("A hit uses its marked snippet first, else its excerpt, else nothing")
    func fromHit() {
        let marked = LookoutUIFixtures.hit("/a.txt", snippet: "the «pet» clause", excerpt: "the pet clause")
        #expect(LookoutSnippet(hit: marked, terms: [])?.runs.filter(\.isMatch).map(\.text) == ["pet"])
        let excerpt = LookoutUIFixtures.hit("/b.txt", excerpt: "the pet clause")
        #expect(LookoutSnippet(hit: excerpt, terms: ["clause"])?.runs.filter(\.isMatch).map(\.text) == ["clause"])
        #expect(LookoutSnippet(hit: LookoutUIFixtures.hit("/c.png", kind: .image), terms: ["dog"]) == nil)
    }
}
