import Foundation
import Testing
@testable import DeeDock

struct UpdateComicParserTests {
    @Test("Locked markdown yields paired German and English panels")
    func parsesLockedShape() throws {
        let comic = try #require(UpdateComicParser.parse(Self.fixtureMarkdown))
        #expect(comic.title == "DDock 9.9.9 What’s New")
        #expect(comic.panels.map(\.id) == ["01", "02"])
        #expect(comic.panels.map(\.imagePath) == [
            "assets/9.9.9/panel-01.png",
            "assets/9.9.9/panel-02.png"
        ])

        let first = comic.panels[0]
        #expect(first.german.topic == "Karten")
        #expect(first.german.title == "Eine kurze Überschrift")
        #expect(first.german.speech == "Hallo vom Dock.")
        #expect(first.german.caption.contains("Bildunterschrift"))
        #expect(first.german.alt.contains("Karte"))
        #expect(first.english.topic == "Cards")
        #expect(first.english.title == "A short heading")
        #expect(first.english.speech == "Hello from the dock.")
        #expect(first.english.caption.contains("caption"))
        #expect(first.english.alt.contains("card"))

        let second = comic.panels[1]
        #expect(second.german.speech.isEmpty)
        #expect(second.english.speech.isEmpty)
        #expect(second.german.title == "Zweiter Titel hier")
        #expect(second.english.title == "Second title here")

        #expect(first.german.wordCount(of: first.german.title) <= UpdateComicCopy.titleWordLimit)
        #expect(first.german.wordCount(of: first.german.speech) <= UpdateComicCopy.speechWordLimit)
        #expect(first.german.wordCount(of: first.german.caption) <= UpdateComicCopy.captionWordLimit)
        #expect(first.english.wordCount(of: first.english.title) <= UpdateComicCopy.titleWordLimit)
        #expect(first.english.wordCount(of: first.english.speech) <= UpdateComicCopy.speechWordLimit)
        #expect(first.english.wordCount(of: first.english.caption) <= UpdateComicCopy.captionWordLimit)
    }

    @Test("A missing English section or empty document is not a comic")
    func rejectsIncompleteDocuments() {
        #expect(UpdateComicParser.parse("") == nil)
        #expect(UpdateComicParser.parse("# Title\n\n## Panel 01 — Nur Deutsch\n") == nil)
        #expect(UpdateComicParser.parse("## English\n\n### Panel 01 — Only English\n") == nil)
    }

    @Test("Oversized markdown is rejected with the notes byte cap")
    func rejectsOversizedMarkdown() {
        let padding = String(repeating: "x", count: UpdateReleaseNotes.maximumBytes)
        #expect(UpdateComicParser.parse(Self.fixtureMarkdown + padding) == nil)
    }

    @Test("A fifth panel heading is ignored; unpaired English panels drop out")
    func capsAndPairsPanels() throws {
        let extra = """
        # DDock 9.9.9 What’s New

        ## Panel 01 — Eins

        ![a](assets/9.9.9/panel-01.png)

        **Titel eins**

        Caption eins.

        ## Panel 05 — Zu viel

        ![e](assets/9.9.9/panel-05.png)

        **Titel fünf**

        Caption fünf.

        ## English

        ### Panel 01 — One

        ![a](assets/9.9.9/panel-01.png)

        **Title one**

        Caption one.
        """
        let comic = try #require(UpdateComicParser.parse(extra))
        #expect(comic.panels.map(\.id) == ["01"])
    }

    @Test("Companion markdown sits next to Sparkle notes or the enclosure ZIP")
    func companionURL() throws {
        let notes = try #require(URL(string: "https://github.com/benjamin-kraatz/DeeDock/releases/download/v9.9.9/DDock.md"))
        let zip = try #require(URL(string: "https://github.com/benjamin-kraatz/DeeDock/releases/download/v9.9.9/DDock.zip"))
        #expect(UpdateComicResourcePolicy.companionMarkdownURL(from: notes)?.lastPathComponent == "DDock-comic.md")
        #expect(UpdateComicResourcePolicy.companionMarkdownURL(from: zip)?.absoluteString.hasSuffix("/v9.9.9/DDock-comic.md") == true)
    }

    @Test("Image paths resolve against the document and fall back to panel-0N.png")
    func imageCandidates() throws {
        let document = try #require(URL(string: "https://github.com/benjamin-kraatz/DeeDock/releases/download/v9.9.9/DDock-comic.md"))
        let urls = UpdateComicResourcePolicy.imageCandidates(path: "assets/9.9.9/panel-01.png", documentURL: document)
        #expect(urls.map(\.lastPathComponent) == ["panel-01.png", "panel-01.png"])
        #expect(urls[0].absoluteString.contains("/v9.9.9/assets/9.9.9/panel-01.png"))
        #expect(urls[1].absoluteString.hasSuffix("/v9.9.9/panel-01.png"))
    }

    @Test("Remote fetches start only on the DeeDock GitHub allowlist")
    func allowlist() throws {
        let release = try #require(URL(string: "https://github.com/benjamin-kraatz/DeeDock/releases/download/v9.9.9/DDock-comic.md"))
        let raw = try #require(URL(string: "https://raw.githubusercontent.com/benjamin-kraatz/DeeDock/main/docs/releases/9.9.9-comic.md"))
        let otherRepo = try #require(URL(string: "https://github.com/octocat/Hello-World/releases/download/v1/DDock-comic.md"))
        let http = try #require(URL(string: "http://github.com/benjamin-kraatz/DeeDock/releases/download/v9.9.9/DDock-comic.md"))
        let fonts = try #require(URL(string: "https://fonts.googleapis.com/css2?family=Inter"))
        let cdn = try #require(URL(string: "https://objects.githubusercontent.com/release-assets/panel-01.png"))
        let file = URL(fileURLWithPath: "/tmp/panel-01.png")

        #expect(UpdateComicResourcePolicy.allowsInitial(release))
        #expect(UpdateComicResourcePolicy.allowsInitial(raw))
        #expect(UpdateComicResourcePolicy.allowsInitial(file))
        #expect(!UpdateComicResourcePolicy.allowsInitial(otherRepo))
        #expect(!UpdateComicResourcePolicy.allowsInitial(http))
        #expect(!UpdateComicResourcePolicy.allowsInitial(fonts))
        #expect(!UpdateComicResourcePolicy.allowsInitial(cdn))
        #expect(UpdateComicResourcePolicy.allowsRedirect(cdn))
        #expect(!UpdateComicResourcePolicy.allowsRedirect(fonts))
    }

    @Test("Local file companion loads copy and PNG bytes without a network hop")
    func loadsLocalCompanion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateComic.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let markdownURL = folder.appendingPathComponent("DDock-comic.md")
        let notesURL = folder.appendingPathComponent("DDock.md")
        try Self.fixtureMarkdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        try Data("notes".utf8).write(to: notesURL)
        let png = Self.oneByOnePNG
        try png.write(to: folder.appendingPathComponent("panel-01.png"))
        try png.write(to: folder.appendingPathComponent("panel-02.png"))

        let comic = try #require(await UpdateComicLoader.load(fromRelatedURL: notesURL))
        #expect(comic.panels.count == 2)
        #expect(comic.panels[0].imageData == png)
        #expect(comic.panels[1].imageData == png)
    }

    private static let fixtureMarkdown = """
    # DDock 9.9.9 What’s New

    Test fixture. Not a shipped release.

    ## Panel 01 — Karten

    ![Deutsche Alt-Beschreibung einer Karte.](assets/9.9.9/panel-01.png)

    **Eine kurze Überschrift**

    > Hallo vom Dock.

    Die Bildunterschrift bleibt lesbar neben der Zeichnung.

    ## Panel 02 — Stapel

    ![Zweite deutsche Alt.](assets/9.9.9/panel-02.png)

    **Zweiter Titel hier**

    Zweite Bildunterschrift ohne Sprechblase.

    ## English

    ### Panel 01 — Cards

    ![English alt for a card.](assets/9.9.9/panel-01.png)

    **A short heading**

    > Hello from the dock.

    The caption stays readable beside the drawing.

    ### Panel 02 — Stacks

    ![Second English alt.](assets/9.9.9/panel-02.png)

    **Second title here**

    Second caption with no speech line.
    """

    private static let oneByOnePNG = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ])
}
