import Foundation
import Testing
@testable import DeeDock

/// How keyword text is normalized and matched (`SearchText`), so a word is found however it was typed or extracted.
struct LookoutSearchTextTests {
    @Test func normalizedFoldsWhatIsTypedDifferently() {
        #expect(SearchText.normalized("الْمَكْتَبَةَ") == "المكتبة")              // harakat
        #expect(SearchText.normalized("إلى الأردن") == "الى الاردن")              // alef forms
        #expect(SearchText.normalized("مـــرحبا") == "مرحبا")                      // tatweel
        #expect(SearchText.normalized("\u{FEFB}") == "\u{0644}\u{0627}")           // the lam-alef ligature
        #expect(SearchText.normalized("\u{FB01}le") == "file")                     // ﬁ
        #expect(SearchText.normalized("র\u{200D}্যাব") == "র্যাব")                  // zero-width joiner
        #expect(SearchText.normalized("\u{09C7}\u{09BE}") == "\u{09CB}")           // ে + া → ো
        #expect(SearchText.normalized("a\u{200B}b") == "a b")                      // zero-width space breaks words
        #expect(SearchText.normalized("Ｒｅｃｅｉｐｔ") == "Receipt")                 // full-width
        #expect(SearchText.normalized("plain text") == "plain text")
    }

    @Test func digitsAloneHaveNoWords() {
        #expect(SearchText.hasWords("Quarterly budget report for 2026"))
        #expect(!SearchText.hasWords("12 345 67.8 9,10 11 12 13 14 15 16"))
        #expect(SearchText.hasWords("কুমির ১২"))   // vowel signs count as letters
        #expect(!SearchText.hasWords(""))
    }

    @Test func matchesAreWholeWordsOrWholeInflectedWords() {
        let text = "The payment failed. Repayment later."
        let found = SearchText.matches(of: "payment", in: text).map { String(text[$0]) }
        #expect(found == ["payment"])   // never the middle of "Repayment"
        let bengali = "সুন্দরবনে আমরা কুমিরও দেখেছি"
        #expect(SearchText.matches(of: "কুমির", in: bengali).map { String(bengali[$0]) } == ["কুমিরও"])
        #expect(SearchText.matches(of: "Café", in: "a cafe on the corner").count == 1)   // accents ignored
    }

    @Test func snippetsMarkTheTermsInTheTextAsWritten() {
        let snippet = SearchText.snippet("We booked the train to Kamakura and dinner in Shibuya.", terms: ["kamakura"])
        #expect(snippet?.contains("«Kamakura»") == true)
        #expect(SearchText.snippet("nothing here", terms: ["zebra"]) == nil)
    }
}
