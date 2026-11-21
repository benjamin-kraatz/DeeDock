import Foundation
import Testing
@testable import DeeDock

/// Names that need a caption, safe rename suggestions, and version families.
struct FlixNamingAndVersionTests {
    // MARK: Cryptic names

    @Test(arguments: ["Screenshot 2026-11-20 at 21.18.png", "IMG_4821.HEIC", "document (3).pdf", "a3f9c2e1b4d5e6f7.pdf",
                      "20261120_143000.jpg", "Untitled.txt", "Bildschirmfoto 2026-11-20 um 09.12.04.png"])
    func crypticNames(_ name: String) {
        #expect(FlixFileNaming.isCryptic(name))
    }

    @Test(arguments: ["Invoice-2026-11.pdf", "Signed contract.pdf", "Oak & Ash quote.pdf", "Launch deck.key"])
    func meaningfulNames(_ name: String) {
        #expect(!FlixFileNaming.isCryptic(name))
    }

    // MARK: Rename suggestions

    @Test func renameKeepsTheExtensionAndCleansCharacters() {
        #expect(FlixFileNaming.sanitizedName("Oak & Ash – Packaging quote", keepingExtensionOf: "document (3).pdf")
                == "Oak & Ash – Packaging quote.pdf")
        #expect(FlixFileNaming.sanitizedName("Q3: Budget/Plan", keepingExtensionOf: "scan.pdf") == "Q3 Budget Plan.pdf")
        #expect(FlixFileNaming.sanitizedName("..hidden  name.", keepingExtensionOf: "IMG_1.png") == "hidden name.png")
        #expect(FlixFileNaming.sanitizedName("Report.PDF", keepingExtensionOf: "x.pdf") == "Report.pdf")
    }

    @Test func renameAvoidsCollisionsAndNoOps() {
        #expect(FlixFileNaming.sanitizedName("Report", keepingExtensionOf: "scan.pdf", taken: ["Report.pdf", "report 2.pdf"])
                == "Report 3.pdf")
        #expect(FlixFileNaming.sanitizedName("Report", keepingExtensionOf: "Report.pdf") == nil)
        #expect(FlixFileNaming.sanitizedName("///", keepingExtensionOf: "scan.pdf") == nil)
        let long = String(repeating: "word ", count: 40)
        let name = FlixFileNaming.sanitizedName(long, keepingExtensionOf: "scan.pdf")
        #expect(name.map { ($0 as NSString).deletingPathExtension.count <= FlixFileNaming.maximumStemLength } == true)
    }

    // MARK: Versions

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func member(_ name: String, at hours: Double, kind: FlixItemKind = .document,
                        vector: [Float]? = nil) -> FlixVersionFamilies.Member {
        FlixVersionFamilies.Member(id: UUID(), name: name, kind: kind, date: t0.addingTimeInterval(hours * 3_600),
                                   vector: vector.map { LookoutFileVector(vector: $0, isPicture: false) })
    }

    @Test func draftsNumbersAndSignedCopiesFormOneFamily() {
        let v2 = member("Contract draft v2.docx", at: 0), v3 = member("Contract draft v3.docx", at: 1)
        let signed = member("Signed contract.pdf", at: 2)
        let groups = FlixVersionFamilies.groups([signed, v3, v2])
        #expect(groups[v2.id]?.rank == 0)
        #expect(groups[v3.id]?.rank == 1)
        #expect(groups[signed.id]?.rank == 2)
        #expect(Set([v2, v3, signed].compactMap { groups[$0.id]?.group }).count == 1)
    }

    @Test func monthlyInvoicesAndCrypticNamesAreNotVersions() {
        let groups = FlixVersionFamilies.groups([
            member("Invoice-2026-11.pdf", at: 0), member("Invoice-2026-10.pdf", at: 1),
            member("document (3).pdf", at: 2), member("document (2).pdf", at: 3),
        ])
        #expect(groups.isEmpty)
    }

    @Test func finderDuplicatesRankAfterTheOriginal() {
        let original = member("Report.pdf", at: 0), copy = member("Report (2).pdf", at: 1)
        let groups = FlixVersionFamilies.groups([original, copy])
        #expect(groups[original.id]?.rank == 0)
        #expect(groups[copy.id]?.rank == 1)
    }

    @Test func differentKindsAndUnrelatedContentStayApart() {
        #expect(FlixVersionFamilies.groups([member("Berlin.jpg", at: 0, kind: .image), member("Berlin v2.pdf", at: 1)]).isEmpty)

        let unrelated = member("Plan v1.pdf", at: 0, vector: [0, 1, 0])
        let related = member("Plan v2.pdf", at: 1, vector: [0.8, 0.6, 0])
        let newest = member("Plan v3.pdf", at: 2, vector: [1, 0, 0])
        let groups = FlixVersionFamilies.groups([unrelated, related, newest])
        #expect(groups[unrelated.id] == nil)
        #expect(groups[related.id]?.rank == 0)
        #expect(groups[newest.id]?.rank == 1)
    }
}
