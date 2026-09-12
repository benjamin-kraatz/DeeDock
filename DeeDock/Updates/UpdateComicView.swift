#if DIRECT_DISTRIBUTION
import AppKit
import SwiftUI

/// Cream paper, indigo ink, and the DEE-38 lilac / mint / coral speech colors.
enum UpdateComicPalette {
    static let paper = Color(red: 0.969, green: 0.945, blue: 0.902)
    static let ink = Color(red: 0.165, green: 0.153, blue: 0.329)
    static let lilac = Color(red: 0.788, green: 0.722, blue: 0.878)
    static let mint = Color(red: 0.718, green: 0.863, blue: 0.784)
    static let coral = Color(red: 0.949, green: 0.714, blue: 0.659)

    static func speechFill(for index: Int) -> Color {
        switch index % 3 {
        case 0: lilac
        case 1: mint
        default: coral
        }
    }
}

/// Responsive What’s New comic. Wide windows keep DE and EN in columns; narrow ones stack.
///
/// Copy is selectable. Art uses the authored alt strings. The view does not animate, so
/// Reduce Motion does not need a separate path.
struct UpdateComicView: View {
    let comic: UpdateComic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !comic.title.isEmpty {
                Text(verbatim: comic.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(UpdateComicPalette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(comic.panels) { panel in
                UpdateComicPanelView(panel: panel)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One cream card: art, then German and English copy.
struct UpdateComicPanelView: View {
    let panel: UpdateComicPanel
    private var speechFill: Color {
        UpdateComicPalette.speechFill(for: (Int(panel.id) ?? 1) - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !panel.german.topic.isEmpty || !panel.english.topic.isEmpty {
                Text(verbatim: topicLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(UpdateComicPalette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            UpdateComicArtworkView(panel: panel)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    UpdateComicCopyView(copy: panel.german, language: .updatesComicGerman,
                                        speechFill: speechFill)
                    UpdateComicCopyView(copy: panel.english, language: .updatesComicEnglish,
                                        speechFill: speechFill)
                }
                VStack(alignment: .leading, spacing: 14) {
                    UpdateComicCopyView(copy: panel.german, language: .updatesComicGerman,
                                        speechFill: speechFill)
                    UpdateComicCopyView(copy: panel.english, language: .updatesComicEnglish,
                                        speechFill: speechFill)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UpdateComicPalette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(UpdateComicPalette.ink.opacity(0.82), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var topicLine: String {
        let number = panel.id
        if !panel.german.topic.isEmpty { return "\(number) / \(panel.german.topic)" }
        return "\(number) / \(panel.english.topic)"
    }
}

/// Panel PNG when bytes decode; otherwise a quiet placeholder that keeps the 3:2 hole.
struct UpdateComicArtworkView: View {
    let panel: UpdateComicPanel

    var body: some View {
        Group {
            if let data = panel.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(verbatim: panel.german.alt))
                    .accessibilityValue(Text(verbatim: panel.english.alt))
            } else {
                ZStack {
                    UpdateComicPalette.paper
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(UpdateComicPalette.ink.opacity(0.35))
                }
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(.updatesComicImageMissing))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(panel.german.alt.isEmpty && panel.english.alt.isEmpty && panel.imageData != nil)
    }
}

/// One language column. Speech, title, and caption stay text, never baked into the PNG.
struct UpdateComicCopyView: View {
    let copy: UpdateComicCopy
    let language: LocalizedStringResource
    let speechFill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language)
                .font(.caption.weight(.semibold))
                .foregroundStyle(UpdateComicPalette.ink.opacity(0.64))
                .textCase(.uppercase)
            Text(verbatim: copy.title)
                .font(.headline)
                .foregroundStyle(UpdateComicPalette.ink)
            if !copy.speech.isEmpty {
                Text(verbatim: copy.speech)
                    .font(.callout)
                    .foregroundStyle(UpdateComicPalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(speechFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !copy.caption.isEmpty {
                Text(verbatim: copy.caption)
                    .font(.body)
                    .foregroundStyle(UpdateComicPalette.ink.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minWidth: 168, alignment: .leading)
        .textSelection(.enabled)
    }
}

#Preview("Comic, wide") {
    ScrollView {
        UpdateComicView(comic: UpdateComicPreviewData.sample)
            .padding(24)
    }
    .frame(width: 720, height: 820)
}

#Preview("Comic, narrow, German") {
    ScrollView {
        UpdateComicView(comic: UpdateComicPreviewData.sample)
            .padding(20)
    }
    .environment(\.locale, Locale(identifier: "de"))
    .frame(width: 420, height: 820)
}

#Preview("Comic, missing art") {
    ScrollView {
        UpdateComicView(comic: UpdateComicPreviewData.missingArt)
            .padding(24)
    }
    .frame(width: 640, height: 700)
}

/// Deterministic What’s New sample. No network, no 0.5.0 release copy.
enum UpdateComicPreviewData {
    static let sample: UpdateComic = {
        let markdown = """
        # DDock 9.9.9 What’s New

        Preview fixture. Not a shipped release.

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
        return UpdateComicParser.parse(markdown) ?? UpdateComic(title: "DDock 9.9.9 What’s New", panels: [])
    }()

    static var missingArt: UpdateComic { sample }
}
#endif
