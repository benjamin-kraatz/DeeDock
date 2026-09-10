import Foundation

/// What a clipboard exhibit holds. Decides its artwork and how it returns to the clipboard.
nonisolated enum ClipboardExhibitKind: String, Codable, CaseIterable, Sendable {
    case text
    case link
    case image
    case files
}

/// Why an exhibit's content was veiled.
nonisolated enum ClipboardRedaction: String, Codable, Sendable {
    /// The secret detector matched while automatic redaction was on.
    case detected
    /// The person chose Redact on the exhibit.
    case manual
}

/// One piece in the collection. ``ClipboardMuseumDocument/exhibits`` keeps them newest first.
///
/// Redaction moves the content into an encrypted vault file (`sealedName`) and clears every
/// plain field that could echo it: text, image, recognized text, and curator wording. Revealing
/// needs the owner's authentication. Shred deletes the vault file, which makes redaction permanent.
nonisolated struct ClipboardExhibit: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Sequential accession number shown on the placard. Never reused, even after Clear.
    var catalogNumber: Int
    var kind: ClipboardExhibitKind
    var acquiredAt: Date
    /// The app that was frontmost when the copy was noticed. macOS does not report the
    /// actual source of a pasteboard write, so this is an approximation.
    var sourceName: String? = nil
    var sourceBundleID: String? = nil
    /// Plain text, a link's absolute string, or newline-separated file paths.
    /// Nil for images and while redacted.
    var text: String? = nil
    /// PNG file name inside the museum's image folder. Nil while redacted.
    var imageName: String? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    /// Characters for text and links, file count for files, zero for images.
    var size = 0
    /// True when text was cut at ``ClipboardMuseumLimits/maximumTextCharacters``.
    var truncated = false
    var redaction: ClipboardRedaction? = nil
    /// Set whenever the detector matched, whether or not the exhibit was redacted.
    var secret: ClipboardSecretKind? = nil
    /// Masked identification such as `ghp_••••`. Never more than a token's public prefix or a
    /// card's last four digits.
    var redactedHint: String? = nil
    /// The name the person gave. Wins over every automatic title; nil means automatic.
    var customTitle: String? = nil
    /// Title suggested by the on-device curator model. Never set for sensitive exhibits.
    var curatedTitle: String? = nil
    /// One-sentence wall text from the on-device curator model.
    var curatorNote: String? = nil
    /// Vision classification labels for images, most confident first. English taxonomy names.
    var imageLabels: [String]? = nil
    /// Text Vision read from an image. Searchable, and checked for secrets like copied text.
    var recognizedText: String? = nil
    /// Encrypted content of a redacted exhibit. Nil after Shred, or if sealing failed.
    var sealedName: String? = nil
    /// Set by "Not a Secret"; the detector no longer flags this exhibit.
    var trusted: Bool? = nil

    var isRedacted: Bool { redaction != nil }
    /// A redacted exhibit whose content can still be revealed.
    var isSealed: Bool { isRedacted && sealedName != nil }

    /// Stored file references, in copy order. Empty for other kinds and while redacted.
    var fileURLs: [URL] {
        guard kind == .files, let text else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var linkURL: URL? {
        guard kind == .link, let text else { return nil }
        return URL(string: text)
    }
}

/// The whole collection and its preferences, stored as one local file.
nonisolated struct ClipboardMuseumDocument: Codable, Equatable, Sendable {
    /// Off until the person turns it on. Nothing is read from the clipboard before that.
    var captureEnabled = false
    var redactSecrets = true
    /// Curator titles and notes, used only when the on-device model is available.
    var curatorEnabled = true
    var nextCatalogNumber = 1
    /// SHA-256 digests of text the person marked "Not a Secret", so the same text is not
    /// flagged again. Only ever holds text the person declared harmless.
    var trustedDigests: [String] = []
    /// Newest first.
    var exhibits: [ClipboardExhibit] = []

    static let maximumTrustedDigests = 500

    init() {}

    var isValid: Bool {
        exhibits.count <= ClipboardMuseumLimits.maximumExhibits
            && nextCatalogNumber > 0
            && trustedDigests.count <= Self.maximumTrustedDigests
            && Set(exhibits.map(\.id)).count == exhibits.count
            && exhibits.allSatisfy { exhibit in
                (exhibit.imageName.map(ClipboardMuseumRepository.isImageName) ?? true)
                    && (exhibit.sealedName.map(ClipboardMuseumRepository.isSealedName) ?? true)
                    && (exhibit.text?.count ?? 0) <= ClipboardMuseumLimits.maximumTextCharacters
                        + ClipboardMuseumLimits.maximumFiles * 4_096
                    && (exhibit.recognizedText?.count ?? 0) <= ClipboardMuseumLimits.maximumTextCharacters
            }
    }

    private enum CodingKeys: String, CodingKey {
        case captureEnabled, redactSecrets, curatorEnabled, nextCatalogNumber, trustedDigests, exhibits
    }

    /// Absent keys take defaults so a later field addition does not strand an older file.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        captureEnabled = try values.decodeIfPresent(Bool.self, forKey: .captureEnabled) ?? false
        redactSecrets = try values.decodeIfPresent(Bool.self, forKey: .redactSecrets) ?? true
        curatorEnabled = try values.decodeIfPresent(Bool.self, forKey: .curatorEnabled) ?? true
        nextCatalogNumber = try values.decodeIfPresent(Int.self, forKey: .nextCatalogNumber) ?? 1
        trustedDigests = try values.decodeIfPresent([String].self, forKey: .trustedDigests) ?? []
        exhibits = try values.decodeIfPresent([ClipboardExhibit].self, forKey: .exhibits) ?? []
    }
}
