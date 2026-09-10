import SwiftUI

/// Wall-label wording and artwork symbols. Clipboard content is always shown verbatim; only the
/// fallbacks are localized.
extension ClipboardExhibit {
    /// Title derived from content alone, or nil when only a localized fallback fits.
    var automaticTitle: String? {
        switch kind {
        case .text:
            let line = (text ?? "").split(whereSeparator: \.isNewline)
                .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return line.map { String($0.prefix(120)) }
        case .link:
            return linkURL?.host() ?? text
        case .image:
            return imageLabels?.first.map(\.localizedCapitalized)
        case .files:
            let urls = fileURLs
            return urls.count == 1 ? urls.first?.lastPathComponent : nil
        }
    }

    /// Precedence: the person's name, the veil, the curator's title, then content.
    var titleText: Text {
        if let customTitle { return Text(verbatim: customTitle) }
        if isRedacted { return redactedHint.map { Text(verbatim: $0) } ?? Text(.clipboardMuseumRedactedTitle) }
        if let curatedTitle { return Text(verbatim: curatedTitle) }
        if let automaticTitle { return Text(verbatim: automaticTitle) }
        switch kind {
        case .image:
            return Text(.clipboardMuseumUntitledImage)
        case .files:
            let urls = fileURLs
            if let first = urls.first, urls.count > 1 {
                return Text(.clipboardMuseumFilesTitle(first.lastPathComponent, urls.count - 1))
            }
            return Text(medium)
        case .text, .link:
            return Text(medium)
        }
    }

    /// The title as a plain string, for file names.
    var plainTitle: String {
        customTitle ?? (isRedacted ? redactedHint : nil) ?? curatedTitle ?? automaticTitle ?? String(localized: medium)
    }

    /// What the rename field starts with: the name the person sees, ready to edit.
    var renameSeed: String {
        customTitle ?? (isRedacted ? "" : curatedTitle ?? automaticTitle ?? "")
    }

    var medium: LocalizedStringResource {
        switch kind {
        case .text: .clipboardMuseumMediumText
        case .link: .clipboardMuseumMediumLink
        case .image: .clipboardMuseumMediumImage
        case .files: .clipboardMuseumMediumFiles
        }
    }

    var symbolName: String {
        if isRedacted { return "lock.fill" }
        switch kind {
        case .text: return "text.quote"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    var dimensionsText: Text? {
        switch kind {
        case .text, .link: Text(.clipboardMuseumCharacters(size))
        case .files: Text(.clipboardMuseumFileCount(size))
        case .image:
            if let pixelWidth, let pixelHeight { Text(.clipboardMuseumPixels(pixelWidth, pixelHeight)) } else { nil }
        }
    }

    /// Searches everything a person might remember: content, names, provenance, curator wording,
    /// and what Vision saw or read in an image.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let fields = [text, sourceName, redactedHint, customTitle, curatedTitle, curatorNote, recognizedText]
            .compactMap(\.self) + (imageLabels ?? [])
        return fields.contains { $0.localizedStandardContains(query) }
    }
}

extension ClipboardSecretKind {
    var title: LocalizedStringResource {
        switch self {
        case .privateKey: .clipboardMuseumSecretPrivateKey
        case .accessToken: .clipboardMuseumSecretAccessToken
        case .webToken: .clipboardMuseumSecretWebToken
        case .cardNumber: .clipboardMuseumSecretCardNumber
        case .credential: .clipboardMuseumSecretCredential
        case .generatedSecret: .clipboardMuseumSecretGenerated
        }
    }
}

/// Gallery wall, mat, and frame colors. The mat stays paper-light in Dark Mode like a real
/// print, so artwork ink is fixed rather than following the system label color.
enum ClipboardMuseumPalette {
    static let ink = Color(red: 0.14, green: 0.13, blue: 0.12)
    static let mat = Color(red: 0.985, green: 0.978, blue: 0.962)
    static let moulding = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let brass = Color(red: 0.72, green: 0.58, blue: 0.34)

    static func wall(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.12, green: 0.115, blue: 0.11) : Color(red: 0.925, green: 0.905, blue: 0.87)
    }

    static func spotlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.32, green: 0.29, blue: 0.24) : Color(red: 1.0, green: 0.985, blue: 0.95)
    }

    static func placard(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.20, green: 0.19, blue: 0.18) : Color(red: 0.975, green: 0.965, blue: 0.945)
    }
}
