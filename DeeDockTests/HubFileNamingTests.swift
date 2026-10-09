import Foundation
import Testing
@testable import DeeDock

struct HubFileNamingTests {
    private let folder = URL(fileURLWithPath: "/tmp/hub-naming", isDirectory: true)
    private let copy = String(localized: .hubFilesCopySuffix)

    private func name(_ name: String, taken: Set<String>) -> String {
        HubFileNaming.availableName(for: name, in: folder) { taken.contains($0.lastPathComponent) }
    }

    @Test func freeNameIsKept() {
        #expect(name("Report.pdf", taken: []) == "Report.pdf")
    }

    @Test func firstCollisionAddsCopyBeforeExtension() {
        #expect(name("Report.pdf", taken: ["Report.pdf"]) == "Report \(copy).pdf")
    }

    @Test func laterCollisionsNumberTheCopy() {
        let taken: Set = ["Report.pdf", "Report \(copy).pdf", "Report \(copy) 2.pdf"]
        #expect(name("Report.pdf", taken: taken) == "Report \(copy) 3.pdf")
    }

    @Test func foldersAndExtensionlessNamesAppendCopy() {
        #expect(name("Folder", taken: ["Folder"]) == "Folder \(copy)")
        #expect(name("Folder", taken: ["Folder", "Folder \(copy)"]) == "Folder \(copy) 2")
    }

    @Test func copyingACopyContinuesTheSequence() {
        let taken: Set = ["Report.pdf", "Report \(copy).pdf"]
        #expect(name("Report \(copy).pdf", taken: taken) == "Report \(copy) 2.pdf")
        #expect(name("Report \(copy) 2.pdf", taken: taken.union(["Report \(copy) 2.pdf"])) == "Report \(copy) 3.pdf")
    }

    @Test func dotFilesAndTrailingDotsHaveNoExtension() {
        #expect(HubFileNaming.split(".zshrc").ext.isEmpty)
        #expect(HubFileNaming.split("notes.").ext.isEmpty)
        let archive = HubFileNaming.split("archive.tar.gz")
        #expect(archive.stem == "archive.tar" && archive.ext == "gz")
        #expect(name(".zshrc", taken: [".zshrc"]) == ".zshrc \(copy)")
    }
}
