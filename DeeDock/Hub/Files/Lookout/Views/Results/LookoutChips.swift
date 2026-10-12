import SwiftUI

/// A Lookout row's two chips (the mockup's `.chips`): what the hit is ("PDF · Page 7", "Folder · 6 matching files")
/// and why it matched ("Meaning", "Exact words", "Meaning + words"). The row reads both to VoiceOver in its value.
struct LookoutChips: View {
    let kind: LookoutHitKind
    let match: LookoutHit.Match
    /// Replaces the match chip's text ("Looks alike", "Same subject" in a search with a picture), in the meaning
    /// style.
    var matchTitle: String?

    var body: some View {
        HStack(spacing: 5) {
            LookoutChip(text: kind.title, style: .neutral)
            LookoutChip(text: matchTitle ?? match.title, style: match == .words && matchTitle == nil ? .words : .meaning)
        }
    }
}

/// One small rounded label.
struct LookoutChip: View {
    enum Style {
        /// Gray, for the kind.
        case neutral
        /// The Lookout accent: matched by meaning (alone or with words).
        case meaning
        /// The highlight yellow: matched by the exact words only.
        case words
    }

    let text: String
    let style: Style

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let (fill, ink): (Color, AnyShapeStyle) = switch style {
        case .neutral: (HubFilesTheme(scheme).chip, AnyShapeStyle(.secondary))
        case .meaning: (lookout.accentSoft, AnyShapeStyle(lookout.accent))
        case .words: (lookout.mark, AnyShapeStyle(lookout.markText))
        }
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill, in: .rect(cornerRadius: 6))
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: 8) {
        LookoutChips(kind: .pdf(page: 7), match: .meaning)
        LookoutChips(kind: .screenshot, match: .both)
        LookoutChips(kind: .document, match: .words)
        LookoutChips(kind: .folder(matchingFiles: 6), match: .meaning)
        LookoutChips(kind: .picture, match: .meaning, matchTitle: "Looks alike")
    }
    .padding(20)
    .background(.regularMaterial)
}
