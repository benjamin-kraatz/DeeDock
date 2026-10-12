import Testing
@testable import DeeDock

/// Where a Lookout hit is, shown from the home folder down: "Desktop › Holiday Sylt 2026".
struct LookoutLocationTests {
    private let home = "/Users/tester"

    @Test("Folders under home join with › from the first folder")
    func underHome() {
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/Desktop/Holiday Sylt 2026/IMG_4821.HEIC", home: home)
            == "Desktop › Holiday Sylt 2026")
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/Downloads/receipt.pdf", home: home) == "Downloads")
    }

    @Test("The first folder takes its localized name; deeper ones keep theirs")
    func localizedFirstFolder() {
        let names = ["/Users/tester/Desktop": "Schreibtisch", "/Users/tester/Desktop/Work": "never used"]
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/Desktop/Work/a.txt", home: home) { names[$0] }
            == "Schreibtisch › Work")
    }

    @Test("A file in home shows home's name; a folder hit shows its parent")
    func homeAndFolders() {
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/notes.md", home: home) == "tester")
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/notes.md", home: home + "/") == "tester")
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/Documents/Steuern 2025", home: home) == "Documents")
        #expect(LookoutLocation.text(forParentOf: "/Users/tester/Documents/Steuern 2025/", home: home) == "Documents")
    }

    @Test("Another volume starts at its name; anything else shows its full path, or / at the root")
    func outsideHome() {
        #expect(LookoutLocation.text(forParentOf: "/Volumes/USB-Stick/Photos/a.jpg", home: home) == "USB-Stick › Photos")
        #expect(LookoutLocation.text(forParentOf: "/Users/testerish/a.txt", home: home) == "Users › testerish")
        #expect(LookoutLocation.text(forParentOf: "/notes.txt", home: home) == "/")
    }
}
