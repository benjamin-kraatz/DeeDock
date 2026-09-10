import CryptoKit
import Foundation
import Observation

/// The collection, its preferences, and every edit to it.
///
/// Collecting is off by default and `accession` ignores captures while it is off, so a stray
/// caller cannot fill the museum behind the person's back. Corrupt storage freezes edits until an
/// explicit reset, so the unreadable file is never silently replaced. Authentication for reveal and
/// un-redact happens in the controller; the store only enforces that content exists to open.
@MainActor @Observable
final class ClipboardMuseumStore {
    private(set) var document = ClipboardMuseumDocument()
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored let repository: ClipboardMuseumRepository
    @ObservationIgnored let vault: ClipboardMuseumVault
    /// Hash of the latest accession, kept in memory only and seeded per process by `Hasher`, so a
    /// repeated copy does not add a duplicate and nothing derived from content is written to disk.
    @ObservationIgnored private var lastFingerprint: Int?

    var captureEnabled: Bool { document.captureEnabled }
    var redactSecrets: Bool { document.redactSecrets }
    var curatorEnabled: Bool { document.curatorEnabled }
    var exhibits: [ClipboardExhibit] { document.exhibits }
    var isEmpty: Bool { document.exhibits.isEmpty }

    init(repository: ClipboardMuseumRepository = ClipboardMuseumRepository(),
         vault: ClipboardMuseumVault = .keychain) {
        self.repository = repository
        self.vault = vault
    }

    /// Loads the stored collection and removes orphaned files.
    func start() {
        do {
            if let stored = try repository.load() { document = stored }
            repository.prune(keepingImages: Set(document.exhibits.compactMap(\.imageName)),
                             sealed: Set(document.exhibits.compactMap(\.sealedName)))
        } catch {
            requiresReset = true
            storageFailed = true
        }
    }

    func exhibit(_ id: UUID) -> ClipboardExhibit? {
        document.exhibits.first { $0.id == id }
    }

    // MARK: Preferences

    func setCaptureEnabled(_ enabled: Bool) {
        guard !requiresReset, document.captureEnabled != enabled else { return }
        document.captureEnabled = enabled
        lastFingerprint = nil
        persist()
    }

    /// Turning redaction on also veils exhibits already flagged as sensitive.
    func setRedactSecrets(_ enabled: Bool) {
        guard !requiresReset, document.redactSecrets != enabled else { return }
        document.redactSecrets = enabled
        if enabled {
            for index in document.exhibits.indices
            where document.exhibits[index].secret != nil && !document.exhibits[index].isRedacted {
                veil(&document.exhibits[index], reason: .detected)
            }
        }
        persist()
    }

    func setCuratorEnabled(_ enabled: Bool) {
        guard !requiresReset, document.curatorEnabled != enabled else { return }
        document.curatorEnabled = enabled
        persist()
    }

    // MARK: Collecting

    /// Adds a capture as the newest exhibit.
    ///
    /// - Returns: The stored exhibit, or nil when collecting is off, storage is frozen, the
    ///   capture repeats the previous one, or it holds nothing worth showing.
    @discardableResult
    func accession(_ capture: ClipboardCapture, at date: Date = .now) -> ClipboardExhibit? {
        guard !requiresReset, document.captureEnabled else { return nil }
        let fingerprint = capture.fingerprint
        guard fingerprint != lastFingerprint, let exhibit = makeExhibit(from: capture, at: date) else { return nil }
        lastFingerprint = fingerprint
        document.exhibits.insert(exhibit, at: 0)
        document.nextCatalogNumber += 1
        while document.exhibits.count > ClipboardMuseumLimits.maximumExhibits {
            discardFiles(of: document.exhibits.removeLast())
        }
        persist()
        return exhibit
    }

    /// Stores Vision results for an image. Text in the image is checked for secrets like copied text.
    func applyAnalysis(_ id: UUID, _ analysis: ClipboardImageAnalysis) {
        guard !requiresReset, let index = index(of: id), document.exhibits[index].kind == .image,
              !document.exhibits[index].isRedacted else { return }
        var exhibit = document.exhibits[index]
        exhibit.imageLabels = analysis.labels.isEmpty ? nil : Array(analysis.labels.prefix(8))
        let text = analysis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        exhibit.recognizedText = text.isEmpty ? nil : String(text.prefix(ClipboardMuseumLimits.maximumTextCharacters))
        if let recognized = exhibit.recognizedText, exhibit.trusted != true,
           let secret = ClipboardSecretDetector.detect(recognized) {
            exhibit.secret = secret
            if document.redactSecrets { veil(&exhibit, reason: .detected) }
        }
        document.exhibits[index] = exhibit
        persist()
    }

    /// Stores curator wording. Refused for anything sensitive, so model output about a secret never persists.
    func applyCuration(_ id: UUID, title: String, note: String) {
        guard !requiresReset, let index = index(of: id), !document.exhibits[index].isRedacted,
              document.exhibits[index].secret == nil else { return }
        document.exhibits[index].curatedTitle = title.isEmpty ? nil : String(title.prefix(80))
        document.exhibits[index].curatorNote = note.isEmpty ? nil : String(note.prefix(240))
        persist()
    }

    /// What the curator may read: never redacted or flagged exhibits.
    func curatorInput(for id: UUID) -> ClipboardCuratorInput? {
        guard let exhibit = exhibit(id), !exhibit.isRedacted, exhibit.secret == nil else { return nil }
        let content: String
        switch exhibit.kind {
        case .text, .link:
            content = exhibit.text ?? ""
        case .files:
            content = exhibit.fileURLs.map(\.lastPathComponent).joined(separator: "\n")
        case .image:
            let labels = exhibit.imageLabels ?? []
            guard !labels.isEmpty || exhibit.recognizedText != nil else { return nil }
            content = ["Vision labels: " + labels.joined(separator: ", "),
                       "Text in image:", exhibit.recognizedText ?? ""].joined(separator: "\n")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ClipboardCuratorInput(medium: exhibit.kind.rawValue, content: String(trimmed.prefix(3_000)))
    }

    // MARK: Editing

    /// Sets the person's name for an exhibit. Blank text returns it to its automatic title.
    func rename(_ id: UUID, to title: String?) {
        guard !requiresReset, let index = index(of: id) else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = trimmed.isEmpty ? nil : String(trimmed.prefix(120))
        guard document.exhibits[index].customTitle != value else { return }
        document.exhibits[index].customTitle = value
        persist()
    }

    /// Hides the exhibit's content in the vault and keeps its placard.
    func redact(_ id: UUID) {
        guard !requiresReset, let index = index(of: id), !document.exhibits[index].isRedacted else { return }
        veil(&document.exhibits[index], reason: .manual)
        persist()
    }

    /// Decrypts a redacted exhibit's content without changing the collection.
    /// Callers must authenticate the owner first.
    func reveal(_ id: UUID) -> ClipboardVeiledPayload? {
        guard let exhibit = exhibit(id), exhibit.isRedacted, let name = exhibit.sealedName,
              let data = try? repository.readSealed(named: name) else { return nil }
        return try? vault.open(data)
    }

    /// Permanently restores a redacted exhibit and trusts its text from now on.
    /// Callers must authenticate the owner first.
    @discardableResult
    func unredact(_ id: UUID) -> Bool {
        guard !requiresReset, let index = index(of: id), let payload = reveal(id) else { return false }
        var exhibit = document.exhibits[index]
        if let image = payload.image {
            guard let name = try? repository.writeImage(image) else {
                storageFailed = true
                return false
            }
            exhibit.imageName = name
        }
        exhibit.text = payload.text
        exhibit.recognizedText = payload.recognizedText
        if let name = exhibit.sealedName { repository.removeSealed(named: name) }
        exhibit.sealedName = nil
        exhibit.redaction = nil
        exhibit.secret = nil
        exhibit.redactedHint = nil
        exhibit.trusted = true
        for text in [payload.text, payload.recognizedText].compactMap(\.self) { trust(text) }
        document.exhibits[index] = exhibit
        persist()
        return true
    }

    /// Deletes a redacted exhibit's encrypted content. Redaction becomes permanent.
    func shred(_ id: UUID) {
        guard !requiresReset, let index = index(of: id), let name = document.exhibits[index].sealedName else { return }
        repository.removeSealed(named: name)
        document.exhibits[index].sealedName = nil
        persist()
    }

    func remove(_ id: UUID) {
        guard !requiresReset, let index = index(of: id) else { return }
        discardFiles(of: document.exhibits.remove(at: index))
        persist()
    }

    /// Deletes every exhibit and file. Preferences and the next catalog number stay, so
    /// accession numbers are never reused.
    func clear() {
        guard !requiresReset else { return }
        document.exhibits.forEach(discardFiles)
        document.exhibits = []
        lastFingerprint = nil
        persist()
    }

    /// Replaces an unreadable collection after an explicit request. Collecting returns to off.
    func reset() {
        try? repository.removeAll()
        document = ClipboardMuseumDocument()
        lastFingerprint = nil
        requiresReset = false
        storageFailed = false
    }

    func imageURL(for exhibit: ClipboardExhibit) -> URL? {
        exhibit.imageName.flatMap(repository.imageURL(named:))
    }

    func imageData(for exhibit: ClipboardExhibit) -> Data? {
        imageURL(for: exhibit).flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: Private

    private func index(of id: UUID) -> Int? {
        document.exhibits.firstIndex { $0.id == id }
    }

    private func makeExhibit(from capture: ClipboardCapture, at date: Date) -> ClipboardExhibit? {
        var exhibit = ClipboardExhibit(id: UUID(), catalogNumber: document.nextCatalogNumber, kind: .text,
                                       acquiredAt: date,
                                       sourceName: capture.source.name.map { String($0.prefix(200)) },
                                       sourceBundleID: capture.source.bundleID.map { String($0.prefix(200)) })
        switch capture.payload {
        case .text(let raw):
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let text = String(raw.prefix(ClipboardMuseumLimits.maximumTextCharacters))
            exhibit.text = text
            exhibit.size = text.count
            exhibit.truncated = text.count < raw.count
            classify(&exhibit, text)
        case .link(let url):
            let text = url.absoluteString
            guard text.count <= ClipboardMuseumLimits.maximumTextCharacters else { return nil }
            exhibit.kind = .link
            exhibit.text = text
            exhibit.size = text.count
            classify(&exhibit, text)
        case .files(let urls):
            // Newlines separate stored paths, so a path containing one cannot be represented.
            let paths = urls.prefix(ClipboardMuseumLimits.maximumFiles).map(\.path)
                .filter { !$0.isEmpty && !$0.contains("\n") && $0.count <= 4_096 }
            guard !paths.isEmpty else { return nil }
            exhibit.kind = .files
            exhibit.text = paths.joined(separator: "\n")
            exhibit.size = paths.count
        case .image(let png, let width, let height):
            guard let name = try? repository.writeImage(png) else {
                storageFailed = true
                return nil
            }
            exhibit.kind = .image
            exhibit.imageName = name
            exhibit.pixelWidth = width
            exhibit.pixelHeight = height
        }
        return exhibit
    }

    private func classify(_ exhibit: inout ClipboardExhibit, _ text: String) {
        guard !document.trustedDigests.contains(Self.digest(text)),
              let secret = ClipboardSecretDetector.detect(text) else { return }
        exhibit.secret = secret
        if document.redactSecrets { veil(&exhibit, reason: .detected) }
    }

    /// Seals content into the vault, then clears every plain field that could echo it. When
    /// sealing fails (for example, the Keychain refuses), the content is dropped rather than left
    /// in plain view, and the exhibit reads as shredded.
    private func veil(_ exhibit: inout ClipboardExhibit, reason: ClipboardRedaction) {
        if let source = exhibit.text ?? exhibit.recognizedText, let secret = exhibit.secret {
            exhibit.redactedHint = ClipboardSecretDetector.hint(for: source, secret: secret)
        }
        let payload = ClipboardVeiledPayload(text: exhibit.text,
                                             image: exhibit.imageName.flatMap { name in
                                                 repository.imageURL(named: name).flatMap { try? Data(contentsOf: $0) }
                                             },
                                             recognizedText: exhibit.recognizedText)
        if !payload.isEmpty, let sealed = try? vault.seal(payload), let name = try? repository.writeSealed(sealed) {
            exhibit.sealedName = name
        }
        if let name = exhibit.imageName { repository.removeImage(named: name) }
        exhibit.text = nil
        exhibit.imageName = nil
        exhibit.recognizedText = nil
        exhibit.curatedTitle = nil
        exhibit.curatorNote = nil
        exhibit.redaction = reason
    }

    private func trust(_ text: String) {
        let digest = Self.digest(text)
        guard !document.trustedDigests.contains(digest) else { return }
        document.trustedDigests.append(digest)
        if document.trustedDigests.count > ClipboardMuseumDocument.maximumTrustedDigests {
            document.trustedDigests.removeFirst(document.trustedDigests.count - ClipboardMuseumDocument.maximumTrustedDigests)
        }
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func discardFiles(of exhibit: ClipboardExhibit) {
        if let name = exhibit.imageName { repository.removeImage(named: name) }
        if let name = exhibit.sealedName { repository.removeSealed(named: name) }
    }

    private func persist() {
        do {
            try repository.save(document)
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }
}
