import AppKit
import SwiftUI

/// The piece inside the frame, drawn by medium. A redacted exhibit shows its veil unless its
/// content has been revealed after authentication.
struct ClipboardExhibitArtwork: View {
    let exhibit: ClipboardExhibit
    let imageURL: URL?
    /// Decrypted content of a redacted exhibit, held only by the presenting view.
    var revealed: ClipboardVeiledPayload? = nil
    /// The largest area the piece may take; the slideshow passes a bigger one.
    var maxSize = CGSize(width: 520, height: 420)

    var body: some View {
        Group {
            if exhibit.isRedacted {
                if let revealed {
                    revealedArtwork(revealed)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ClipboardExhibitVeil(hint: exhibit.redactedHint, sealed: exhibit.isSealed)
                        .transition(.opacity)
                }
            } else {
                switch exhibit.kind {
                case .text: ClipboardExhibitTextArtwork(text: exhibit.text ?? "", width: maxSize.width)
                case .link: ClipboardExhibitLinkArtwork(url: exhibit.linkURL, text: exhibit.text ?? "")
                case .image: ClipboardExhibitImageArtwork(source: .file(imageURL), maxSize: maxSize)
                case .files: ClipboardExhibitFilesArtwork(urls: exhibit.fileURLs)
                }
            }
        }
        .foregroundStyle(ClipboardMuseumPalette.ink)
    }

    @ViewBuilder private func revealedArtwork(_ payload: ClipboardVeiledPayload) -> some View {
        if let image = payload.image {
            ClipboardExhibitImageArtwork(source: .data(image), maxSize: maxSize)
        } else if exhibit.kind == .link, let text = payload.text {
            ClipboardExhibitLinkArtwork(url: URL(string: text), text: text)
        } else if exhibit.kind == .files, let text = payload.text {
            ClipboardExhibitFilesArtwork(urls: text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
        } else {
            ClipboardExhibitTextArtwork(text: payload.text ?? payload.recognizedText ?? "", width: maxSize.width)
        }
    }
}

/// Copied prose set like a printed page. Selectable, so a part can be copied out again.
private struct ClipboardExhibitTextArtwork: View {
    /// Long pieces are shown in part; the full stored text is still restored by Copy.
    private static let displayLimit = 6_000
    let text: String
    let width: CGFloat

    var body: some View {
        Text(verbatim: text.count > Self.displayLimit ? String(text.prefix(Self.displayLimit)) + "…" : text)
            .font(.system(.body, design: .serif))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ClipboardExhibitLinkArtwork: View {
    let url: URL?
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 30, weight: .light))
                .accessibilityHidden(true)
            Text(verbatim: url?.host() ?? text)
                .font(.system(.title2, design: .serif).weight(.medium))
                .multilineTextAlignment(.center)
            Text(verbatim: text)
                .font(.system(.caption, design: .monospaced))
                .opacity(0.7)
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let url {
                Link(destination: url) { Text(.clipboardMuseumOpenLink) }
                    .font(.callout)
            }
        }
        .frame(minWidth: 260, maxWidth: 480)
    }
}

/// Where image bytes come from: the stored PNG, or revealed bytes held in memory.
enum ClipboardImageSource: Equatable {
    case file(URL?)
    case data(Data)
}

/// Loads and decodes off the main actor so a large image never stalls selection or a slide change.
private struct ClipboardExhibitImageArtwork: View {
    let source: ClipboardImageSource
    let maxSize: CGSize
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                    .accessibilityLabel(Text(.clipboardMuseumUntitledImage))
            } else if failed {
                Label { Text(.clipboardMuseumImageMissing) } icon: { Image(systemName: "photo.badge.exclamationmark") }
                    .frame(width: 260, height: 160)
            } else {
                ProgressView().frame(width: 260, height: 160)
            }
        }
        .task(id: source) {
            image = nil
            failed = false
            let data: Data?
            switch source {
            case .file(let url):
                guard let url else { failed = true; return }
                data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            case .data(let bytes):
                data = bytes
            }
            guard !Task.isCancelled else { return }
            if let data, let loaded = NSImage(data: data) { image = loaded } else { failed = true }
        }
    }
}

private struct ClipboardExhibitFilesArtwork: View {
    private static let shownFiles = 12
    let urls: [URL]

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 112), spacing: 14)], spacing: 14) {
                ForEach(urls.prefix(Self.shownFiles), id: \.self) { ClipboardExhibitFileTile(url: $0) }
            }
            if urls.count > Self.shownFiles {
                Text(.clipboardMuseumMoreFiles(urls.count - Self.shownFiles))
                    .font(.caption)
                    .opacity(0.7)
            }
        }
        .frame(minWidth: 240, maxWidth: 520)
    }
}

/// A file's Finder icon and name. Files moved or deleted since the copy are dimmed.
private struct ClipboardExhibitFileTile: View {
    let url: URL

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
                .opacity(exists ? 1 : 0.4)
                .accessibilityHidden(true)
            Text(verbatim: url.lastPathComponent)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opacity(exists ? 1 : 0.5)
        }
        .frame(width: 100)
        .help(Text(verbatim: url.path))
        .accessibilityElement(children: .combine)
    }
}

/// Black censor bars over a redacted piece. The bars are decoration, not hidden content.
struct ClipboardExhibitVeil: View {
    let hint: String?
    /// True when encrypted content remains and can be revealed.
    let sealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([0.94, 0.72, 0.86, 0.48], id: \.self) { fraction in
                Rectangle()
                    .fill(ClipboardMuseumPalette.ink)
                    .frame(width: 320 * fraction, height: 13)
            }
            HStack(spacing: 8) {
                Label { Text(.clipboardMuseumVeilLabel) } icon: { Image(systemName: sealed ? "lock.fill" : "flame.fill") }
                    .font(.caption.weight(.semibold))
                if let hint {
                    Text(verbatim: hint).font(.system(.caption, design: .monospaced))
                }
            }
            .opacity(0.75)
            .padding(.top, 4)
            if sealed {
                Text(.clipboardMuseumVeilSealedNote)
                    .font(.caption2)
                    .opacity(0.55)
            }
        }
        .frame(width: 320, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.clipboardMuseumVeilLabel))
    }
}
