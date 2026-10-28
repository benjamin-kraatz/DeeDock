import SwiftUI

/// The bar above the results of a search with a picture (the mockup's `.qbar`): the picture, its name, how it was
/// read ("New picture · read in 0.4 s · not saved", "From your index · Page 7 · instant") or a spinner while it's
/// read, and "Back to “…”" when there were words before it.
///
/// Words typed beside the picture (DEE-126) follow its name ("+ “at night”"), and the picture–words slider
/// (`LookoutPictureWordsSlider`) appears beside them. Until there are words, a quiet line says that typing adds them.
///
/// When the bar is narrow, the slider keeps its size, "Back to" is cut in the middle past 180 pt, and the name and
/// the words share what's left: the shorter of the two keeps its size and the longer one is cut.
struct LookoutPictureQueryBar: View {
    let picture: LookoutPictureQuery
    let subtitle: LookoutPictureSubtitle
    /// The words searched before the picture; empty hides "Back to".
    let wordsBefore: String
    /// The words typed beside the picture, as the results were ranked with them; empty for none.
    var words = ""
    /// The picture–words slider's place.
    var wordsWeight = LookoutRanking.pictureWordsWeight
    /// Whether the line about adding words shows: the picture's results are in and there are no words yet.
    var showsWordsHint = false
    let reduceMotion: Bool
    var changeWeight: (Double) -> Void = { _ in }
    var commitWeight: () -> Void = {}
    let goBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// How wide "Back to “…”" may grow before its words are cut in the middle.
    private static let backMaxWidth: CGFloat = 180

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // The words and the slider move the rest of the bar as they come and go: the Hub's spring, or a plain fade
        // under Reduce Motion.
        let settle: Animation? = reduceMotion ? .easeOut(duration: 0.15) : HubFilesMotion.layout
        HStack(spacing: 12) {
            LookoutPictureThumbnail(picture: picture, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                // Neither text has layout priority, so under pressure the shorter one is sized first and keeps its
                // words while the longer one is cut: a long screenshot name gives way to short typed words, and a
                // long run of words gives way to a short name.
                HStack(spacing: 5) {
                    Text(verbatim: picture.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !words.isEmpty {
                        Text(.lookoutPictureWithWords(words))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(lookout.accent)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityLabel(Text(.lookoutPictureWithWordsAccessibility(words)))
                            .transition(arrival(anchor: .leading))
                    }
                }
                HStack(spacing: 6) {
                    if subtitle.isBusy {
                        LookoutPictureSpinner(reduceMotion: reduceMotion)
                    }
                    Text(verbatim: subtitle.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .animation(HubFilesMotion.quick, value: subtitle)
                if showsWordsHint {
                    Text(.lookoutPictureWordsHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !words.isEmpty {
                LookoutPictureWordsSlider(weight: wordsWeight, change: changeWeight, commit: commitWeight)
                    .transition(arrival(anchor: .trailing))
            }
            if !wordsBefore.isEmpty {
                Button(action: goBack) {
                    Text(.lookoutPictureBack(wordsBefore))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                // Its own size up to the cap, then cut in the middle, so a long earlier query can't push the name
                // and the words out of the bar.
                .frame(maxWidth: Self.backMaxWidth)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            shape.fill(lookout.card)
            shape.fill(LinearGradient(stops: [.init(color: lookout.accentSoft, location: 0),
                                              .init(color: .clear, location: 0.75)],
                                      startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8)))
        }
        .overlay { shape.strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
        .animation(settle, value: words.isEmpty)
        .animation(HubFilesMotion.quick, value: showsWordsHint)
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
    }

    /// How the words and the slider come and go: they settle in from the edge they sit against (the words grow out
    /// of the name, the slider out of the bar's trailing side), and only fade under Reduce Motion.
    private func arrival(anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: anchor))
    }
}

/// The 11 pt ring that turns while the picture is read (the mockup's `.spin`); a still ring under Reduce Motion.
private struct LookoutPictureSpinner: View {
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        Group {
            if reduceMotion {
                Circle().strokeBorder(lookout.accent, lineWidth: 1.6)
            } else {
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
                    ZStack {
                        Circle().strokeBorder(lookout.accentSoft, lineWidth: 1.6)
                        Circle().trim(from: 0, to: 0.25)
                            .stroke(lookout.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .padding(0.8)
                    }
                    .rotationEffect(.degrees(turn * 360))
                }
            }
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
    }
}

#Preview("Results bar") {
    VStack(spacing: 6) {
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.dropped, subtitle: .new(seconds: 0.35),
                               wordsBefore: "dog on the beach", reduceMotion: false) {}
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.dropped, subtitle: .waking, wordsBefore: "",
                               reduceMotion: false) {}
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.pasted, subtitle: .pasted(seconds: 1.2),
                               wordsBefore: "", reduceMotion: true) {}
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.similarLease, subtitle: .fromIndex(page: 7),
                               wordsBefore: "pets in the lease", reduceMotion: false) {}
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.dropped, subtitle: .new(seconds: 0.35),
                               wordsBefore: "", showsWordsHint: true, reduceMotion: false) {}
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.dropped, subtitle: .new(seconds: 0.35),
                               wordsBefore: "dog on the beach", words: "at sunset", wordsWeight: 0.4,
                               reduceMotion: false) {}
    }
    .frame(width: 640)
    .padding()
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}

/// The fullest bar in the narrowest Hub: a long name, a long earlier query, words, and the slider, in English and
/// German, so what gets cut first can be checked.
#Preview("Results bar · narrow and full") {
    @Previewable @State var weight = LookoutRanking.pictureWordsWeight
    let screenshot = LookoutPictureQuery.dropped(URL(filePath: "/Users/benn/Desktop/Screenshot 2026-10-11 at 18.40.02.png"))
    let bar = LookoutPictureQueryBar(picture: screenshot, subtitle: .new(seconds: 0.35),
                                     wordsBefore: "the lease agreement for the flat on Hauptstraße",
                                     words: "at sunset over the sea", wordsWeight: weight, reduceMotion: false,
                                     changeWeight: { weight = $0 }) {}
    VStack(spacing: 6) {
        bar
        bar.environment(\.locale, Locale(identifier: "de"))
        LookoutPictureQueryBar(picture: LookoutPicturePreviewData.dropped, subtitle: .new(seconds: 0.35),
                               wordsBefore: "", words: "at sunset", reduceMotion: true) {}
    }
    .frame(width: 520)
    .padding()
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}
