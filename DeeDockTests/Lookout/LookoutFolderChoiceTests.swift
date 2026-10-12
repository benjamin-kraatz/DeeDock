import Foundation
import Testing
@testable import DeeDock

/// Which folders Lookout may read: refusals, nested folders, and which folders make macOS ask first.
struct LookoutFolderChoiceTests {
    private let home = "/Users/tester"

    @Test("The whole disk, the home folder and ~/Library are refused", arguments: [
        ("/", LookoutFolderChoice.Refusal.wholeDisk),
        ("", .wholeDisk),
        ("/Users/tester", .homeFolder),
        ("/Users/tester/", .homeFolder),
        ("/Users/tester/Library", .library),
        ("/Users/tester/Library/Mobile Documents/com~apple~CloudDocs", .library),
    ])
    func refusals(path: String, refusal: LookoutFolderChoice.Refusal) {
        #expect(LookoutFolderChoice.refusal(for: path, home: home) == refusal)
        #expect(LookoutFolderChoice.choose(path, chosen: [], home: home) == .refused(refusal))
    }

    @Test("Ordinary folders, including ones whose name merely starts like Library, are accepted")
    func accepted() {
        #expect(LookoutFolderChoice.refusal(for: "/Users/tester/Documents", home: home) == nil)
        #expect(LookoutFolderChoice.refusal(for: "/Users/tester/Library Books", home: home) == nil)
        #expect(LookoutFolderChoice.refusal(for: "/Volumes/Archive", home: home) == nil)
        #expect(LookoutFolderChoice.refusal(for: "/Users/other", home: home) == nil)
    }

    @Test("A folder inside a chosen one adds nothing")
    func nestedIsAlreadyIncluded() {
        let chosen = ["/Users/tester/Documents"]
        #expect(LookoutFolderChoice.choose("/Users/tester/Documents/Taxes", chosen: chosen, home: home)
            == .alreadyIncluded(by: "/Users/tester/Documents"))
        #expect(LookoutFolderChoice.choose("/Users/tester/Documents/", chosen: chosen, home: home)
            == .alreadyIncluded(by: "/Users/tester/Documents"))
        // A sibling whose name starts the same is not inside.
        #expect(LookoutFolderChoice.choose("/Users/tester/Documents Old", chosen: chosen, home: home)
            == .add("/Users/tester/Documents Old", replacing: []))
    }

    @Test("A folder around chosen ones replaces them")
    func parentReplacesChildren() {
        let chosen = ["/Users/tester/Work/Design", "/Users/tester/Work/Notes", "/Users/tester/Desktop"]
        #expect(LookoutFolderChoice.choose("/Users/tester/Work", chosen: chosen, home: home)
            == .add("/Users/tester/Work", replacing: ["/Users/tester/Work/Design", "/Users/tester/Work/Notes"]))
    }

    @Test("Adding to the draft de-duplicates: an added folder inside goes, a suggested one is unchecked")
    func draftDeduplicates() {
        var draft = LookoutSetupDraft(home: home)
        draft.add("/Users/tester/Documents/Work/Design")
        #expect(draft.addNotice == .alreadyIncluded(by: "/Users/tester/Documents"))
        draft.setChosen("/Users/tester/Documents", false)
        draft.add("/Users/tester/Documents/Work/Design")
        #expect(draft.chosen.map(\.path).contains("/Users/tester/Documents/Work/Design"))
        draft.add("/Users/tester/Documents")
        #expect(draft.folders.filter { $0.path == "/Users/tester/Documents/Work/Design" }.isEmpty)
        #expect(draft.folder("/Users/tester/Documents")?.isChosen == true)
        draft.add("/Users/tester/Pictures")
        #expect(draft.folder("/Users/tester/Pictures")?.isChosen == true)
        #expect(draft.folders.count == 4, "no second Pictures row")
        draft.add("/")
        #expect(draft.addNotice == .refused(.wholeDisk))
    }

    @Test("Desktop, Documents, Downloads, iCloud Drive and other volumes need a prompt; Pictures doesn't")
    func prompts() {
        for path in ["Desktop", "Documents", "Downloads", "Documents/Taxes", "Library/Mobile Documents/x"] {
            #expect(LookoutFolderChoice.needsPrompt(home + "/" + path, home: home), "\(path)")
        }
        #expect(LookoutFolderChoice.needsPrompt("/Volumes/Archive/Scans", home: home))
        for path in ["/Users/tester/Pictures", "/Users/tester/Projects", "/Users/tester/Desktop Backup"] {
            #expect(!LookoutFolderChoice.needsPrompt(path, home: home), "\(path)")
        }
    }

    @Test("Paths show with ~ for the home folder")
    func tildePaths() {
        #expect(LookoutSetupFolder.tildePath("/Users/tester/Desktop", home: home) == "~/Desktop")
        #expect(LookoutSetupFolder.tildePath("/Users/tester", home: home) == "~")
        #expect(LookoutSetupFolder.tildePath("/Users/testers/Desktop", home: home) == "/Users/testers/Desktop")
        #expect(LookoutSetupFolder.tildePath("/Volumes/Archive", home: home) == "/Volumes/Archive")
    }
}
