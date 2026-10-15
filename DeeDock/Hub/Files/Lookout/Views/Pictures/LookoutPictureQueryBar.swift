import SwiftUI

/// The bar above the results of a search with a picture (the mockup's `.qbar`): the picture, its name, how it was
/// read ("New picture · read in 0.4 s · not saved", "From your index · Page 7 · instant") or a spinner while it's
/// read, and "Back to “…”" when there were words before it.
struct LookoutPictureQueryBar: View {
    let picture: LookoutPictureQuery
    let subtitle: LookoutPictureSubtitle
    /// The words searched before the picture; empty hides "Back to".
    let wordsBefore: String
    let reduceMotion: Bool
    let goBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 12) {
            LookoutPictureThumbnail(picture: picture, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: picture.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if !wordsBefore.isEmpty {
                Button(action: goBack) {
                    Text(.lookoutPictureBack(wordsBefore))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .fixedSize()
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
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
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
    }
    .frame(width: 640)
    .padding()
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}
