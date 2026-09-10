import AppKit
import CryptoKit
import Foundation
import Testing

@MainActor
struct ClipboardMuseumTests {
    /// A temporary folder and an in-memory vault key, so tests never touch the real collection or Keychain.
    private func makeStore() -> (ClipboardMuseumStore, ClipboardMuseumRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMuseumTests-\(UUID().uuidString)", isDirectory: true)
        let repository = ClipboardMuseumRepository(directory: directory)
        let key = SymmetricKey(size: .bits256)
        return (ClipboardMuseumStore(repository: repository, vault: ClipboardMuseumVault(key: { key })), repository)
    }

    private func collecting() -> (ClipboardMuseumStore, ClipboardMuseumRepository) {
        let (store, repository) = makeStore()
        store.start()
        store.setCaptureEnabled(true)
        return (store, repository)
    }

    private func text(_ value: String) -> ClipboardCapture {
        ClipboardCapture(payload: .text(value), source: ClipboardSource(name: "Notes", bundleID: "com.apple.Notes"))
    }

    private let token = "ghp_" + String(repeating: "Zx9Q", count: 10)

    @Test("Known secret shapes are detected; ordinary clips are left alone")
    func detection() {
        #expect(ClipboardSecretDetector.detect("-----BEGIN OPENSSH PRIVATE KEY-----\nabc") == .privateKey)
        #expect(ClipboardSecretDetector.detect(token) == .accessToken)
        #expect(ClipboardSecretDetector.detect("AKIAABCDEFGHIJKLMNOP") == .accessToken)
        #expect(ClipboardSecretDetector.detect("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N") == .webToken)
        #expect(ClipboardSecretDetector.detect("4242 4242 4242 4242") == .cardNumber)
        #expect(ClipboardSecretDetector.detect("password: hunter22") == .credential)
        #expect(ClipboardSecretDetector.detect("xQ7mK2pL9vR4nT8wZ3bH") == .generatedSecret)

        #expect(ClipboardSecretDetector.detect("Meet at noon on Friday.") == nil)
        #expect(ClipboardSecretDetector.detect("https://example.com/docs/page") == nil)
        #expect(ClipboardSecretDetector.detect("123e4567-e89b-12d3-a456-426614174000") == nil)
        #expect(ClipboardSecretDetector.detect("/Users/me/Documents/Report2024Final.pdf") == nil)
        #expect(ClipboardSecretDetector.detect("MyCompanyName2024Report") == nil)
        #expect(ClipboardSecretDetector.detect("4242 4242 4242 4241") == nil)
        #expect(ClipboardSecretDetector.detect("2026-09-10 12:30") == nil)
    }

    @Test("Hints never reveal more than a vendor prefix or a card's last four digits")
    func hints() {
        #expect(ClipboardSecretDetector.hint(for: "ghp_abcdefghijklmnop", secret: .accessToken) == "ghp_••••")
        #expect(ClipboardSecretDetector.hint(for: "4242 4242 4242 4242", secret: .cardNumber) == "•••• 4242")
        #expect(ClipboardSecretDetector.hint(for: "password: hunter22", secret: .credential) == nil)
    }

    @Test("Collecting is off by default and nothing is stored until it is turned on")
    func offByDefault() {
        let (store, repository) = makeStore()
        defer { try? repository.removeAll() }
        store.start()
        #expect(!store.captureEnabled)
        #expect(store.accession(text("hello")) == nil)
        #expect(store.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repository.documentURL.path))
    }

    @Test("Detected secrets are sealed; the plain value never reaches the collection file")
    func autoRedaction() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let exhibit = try #require(store.accession(text(token)))
        #expect(exhibit.redaction == .detected)
        #expect(exhibit.text == nil)
        #expect(exhibit.isSealed)
        #expect(exhibit.redactedHint == "ghp_••••")
        let bytes = try String(contentsOf: repository.documentURL, encoding: .utf8)
        #expect(!bytes.contains(token))
        #expect(store.reveal(exhibit.id)?.text == token)
    }

    @Test("Not a Secret restores content permanently and stops flagging the same text")
    func unredactTrusts() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let exhibit = try #require(store.accession(text(token)))
        #expect(store.unredact(exhibit.id))
        let restored = try #require(store.exhibit(exhibit.id))
        #expect(!restored.isRedacted)
        #expect(restored.text == token)
        #expect(restored.sealedName == nil)
        #expect(store.accession(text("between")) != nil)
        let again = try #require(store.accession(text(token)))
        #expect(!again.isRedacted)
        #expect(again.secret == nil)
    }

    @Test("Shred makes redaction permanent")
    func shred() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let exhibit = try #require(store.accession(text(token)))
        store.shred(exhibit.id)
        #expect(store.exhibit(exhibit.id)?.isSealed == false)
        #expect(store.reveal(exhibit.id) == nil)
        #expect(!store.unredact(exhibit.id))
    }

    @Test("With auto-redaction off a secret is flagged, and turning it on seals it")
    func lateRedaction() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        store.setRedactSecrets(false)
        let exhibit = try #require(store.accession(text("password: hunter22")))
        #expect(exhibit.secret == .credential)
        #expect(!exhibit.isRedacted)
        store.setRedactSecrets(true)
        #expect(store.exhibits.first?.isSealed == true)
        #expect(store.exhibits.first?.text == nil)
    }

    @Test("A secret read from an image seals the image and its text")
    func secretInImage() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let image = try #require(store.accession(ClipboardCapture(payload: .image(png: Data([1, 2, 3]), width: 1, height: 1))))
        let url = try #require(store.imageURL(for: image))
        store.applyAnalysis(image.id, ClipboardImageAnalysis(labels: ["screenshot"], text: "api_key = \(token)"))
        let sealed = try #require(store.exhibit(image.id))
        #expect(sealed.isSealed)
        #expect(sealed.recognizedText == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.reveal(image.id)?.image == Data([1, 2, 3]))
    }

    @Test("Vision labels and recognized text are searchable")
    func visionSearch() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let image = try #require(store.accession(ClipboardCapture(payload: .image(png: Data([9]), width: 1, height: 1))))
        store.applyAnalysis(image.id, ClipboardImageAnalysis(labels: ["receipt"], text: "Café Luna total 12,40"))
        let analysed = try #require(store.exhibit(image.id))
        #expect(analysed.matches("receipt"))
        #expect(analysed.matches("luna"))
        #expect(!analysed.matches("invoice"))
    }

    @Test("Renaming sets a custom title; blank returns to automatic")
    func rename() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let exhibit = try #require(store.accession(text("first line\nsecond")))
        store.rename(exhibit.id, to: "  Launch notes  ")
        #expect(store.exhibit(exhibit.id)?.customTitle == "Launch notes")
        #expect(store.exhibit(exhibit.id)?.matches("launch") == true)
        store.rename(exhibit.id, to: "   ")
        #expect(store.exhibit(exhibit.id)?.customTitle == nil)
        #expect(store.exhibit(exhibit.id)?.automaticTitle == "first line")
    }

    @Test("Curator wording is refused for sensitive exhibits")
    func curationGuard() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        store.setRedactSecrets(false)
        let flagged = try #require(store.accession(text("password: hunter22")))
        #expect(store.curatorInput(for: flagged.id) == nil)
        store.applyCuration(flagged.id, title: "Login", note: "A password.")
        #expect(store.exhibit(flagged.id)?.curatedTitle == nil)
        let plain = try #require(store.accession(text("Buy oat milk and coffee")))
        #expect(store.curatorInput(for: plain.id) != nil)
        store.applyCuration(plain.id, title: "Shopping list", note: "Two groceries to buy.")
        #expect(store.exhibit(plain.id)?.matches("shopping") == true)
    }

    @Test("Remove and clear delete files and keep catalog numbers unique")
    func removeClear() throws {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        let image = try #require(store.accession(ClipboardCapture(payload: .image(png: Data([1, 2, 3]), width: 1, height: 1))))
        let url = try #require(store.imageURL(for: image))
        let note = try #require(store.accession(text("a note")))
        store.remove(note.id)
        #expect(store.exhibits.map(\.id) == [image.id])
        store.clear()
        #expect(store.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let next = try #require(store.accession(text("after clear")))
        #expect(next.catalogNumber == 3)
    }

    @Test("A repeated copy is not collected twice in a row")
    func duplicates() {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        #expect(store.accession(text("same")) != nil)
        #expect(store.accession(text("same")) == nil)
        #expect(store.accession(text("other")) != nil)
        #expect(store.accession(text("same")) != nil)
        #expect(store.exhibits.count == 3)
    }

    @Test("The oldest exhibits retire past the collection limit")
    func retention() {
        let (store, repository) = collecting()
        defer { try? repository.removeAll() }
        for index in 0..<(ClipboardMuseumLimits.maximumExhibits + 5) { store.accession(text("clip \(index)")) }
        #expect(store.exhibits.count == ClipboardMuseumLimits.maximumExhibits)
        #expect(store.exhibits.last?.text == "clip 5")
    }

    @Test("An unreadable collection freezes edits until an explicit reset")
    func corruptStorage() throws {
        let (store, repository) = makeStore()
        defer { try? repository.removeAll() }
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: repository.documentURL)
        store.start()
        #expect(store.requiresReset)
        store.setCaptureEnabled(true)
        #expect(!store.captureEnabled)
        store.reset()
        #expect(!store.requiresReset)
        #expect(!FileManager.default.fileExists(atPath: repository.documentURL.path))
    }

    @Test("Markdown export carries title, catalog line, content, and curator note")
    func markdown() {
        var exhibit = ClipboardExhibit(id: UUID(), catalogNumber: 7, kind: .link, acquiredAt: .now,
                                       text: "https://example.com/a", size: 21)
        exhibit.curatorNote = "A sample page."
        let markdown = ClipboardMuseumMarkdown.document(for: exhibit, text: exhibit.text, title: "Example",
                                                        catalogLine: "No. 7 · Link")
        #expect(markdown.hasPrefix("# Example\n\n> No. 7 · Link"))
        #expect(markdown.contains("[example.com](https://example.com/a)"))
        #expect(markdown.contains("_A sample page._"))
    }

    @Test("Concealed pasteboard items are never read; plain text and links are classified")
    func reader() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let concealed = NSPasteboardItem()
        concealed.setString("hunter2", forType: .string)
        concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([concealed])
        guard case .skipped = ClipboardMuseumReader.read(from: pasteboard, source: ClipboardSource()) else {
            Issue.record("Concealed item was read")
            return
        }
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/a", forType: .string)
        guard case .capture(let capture) = ClipboardMuseumReader.read(from: pasteboard, source: ClipboardSource()) else {
            Issue.record("Link was not captured")
            return
        }
        #expect(capture.payload == .link(URL(string: "https://example.com/a")!))
        #expect(ClipboardMuseumReader.link("see https://example.com") == nil)
    }
}
