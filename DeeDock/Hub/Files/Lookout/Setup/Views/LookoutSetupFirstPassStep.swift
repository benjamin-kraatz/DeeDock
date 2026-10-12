import SwiftUI

/// Step 5: the first pass. A ring with the percentage, files read out of all, and the files being read now.
///
/// The feed shows file names from `LookoutIndexStatus.current`, on this Mac only: they never reach analytics or a
/// log. It keeps the last few in this view's state and starts empty each time the step appears.
struct LookoutSetupFirstPassStep: View {
    let progress: LookoutFirstPassProgress
    let current: LookoutIndexStatus.CurrentFile?
    var reduceMotion = HubFilesMotion.reduceMotion
    /// Rows to start with (previews).
    var initialFeed: [LookoutSetupFeedItem] = []

    @State private var feed: [LookoutSetupFeedItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LookoutSetupHeading(title: .lookoutSetupFirstPassTitle, lead: .lookoutSetupFirstPassLead)
            VStack(spacing: 10) {
                LookoutProgressRing(fraction: progress.fraction, reduceMotion: reduceMotion)
                Text(verbatim: countText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                LookoutSetupFeed(items: feed, reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .onAppear { if feed.isEmpty { feed = initialFeed } }
        .onChange(of: current) { _, file in
            guard let file else { return }
            let item = LookoutSetupFeedItem(file: file)
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : HubStyle.motion) {
                feed.insert(item, at: 0)
                if feed.count > LookoutSetupFeed.capacity { feed.removeLast(feed.count - LookoutSetupFeed.capacity) }
            }
        }
    }

    private var countText: String {
        if progress.isCounting { return String(localized: .lookoutSetupFirstPassCounting) }
        return "\(progress.done.formatted()) / " + String(localized: .lookoutSetupFiles(progress.total))
    }
}

/// The 120 pt ring (the mockup's `.ring`): an 8 pt track, the Lookout accent from 12 o'clock, the percentage inside.
struct LookoutProgressRing: View {
    let fraction: Double
    var reduceMotion = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .stroke(HubFilesTheme(scheme).chipHighlight, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(LookoutTheme(scheme).accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: fraction))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        }
        .frame(width: 104, height: 104)
        .padding(8)
        .accessibilityElement()
        .accessibilityLabel(Text(.lookoutSetupFirstPassProgressLabel))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// One file in the feed. Its own identity, so the same name read twice shows twice.
struct LookoutSetupFeedItem: Identifiable, Equatable {
    let id = UUID()
    let file: LookoutIndexStatus.CurrentFile
}

/// The files being read now, newest on top, fading out at the bottom (the mockup's `.feed`).
private struct LookoutSetupFeed: View {
    static let capacity = 5

    let items: [LookoutSetupFeedItem]
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 4) {
            ForEach(items) { item in
                LookoutSetupFeedRow(file: item.file)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 118, alignment: .top)
        .frame(height: 118, alignment: .top)
        .clipped()
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.lookoutSetupFeedLabel))
    }
}

private struct LookoutSetupFeedRow: View {
    let file: LookoutIndexStatus.CurrentFile

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lookout = LookoutTheme(scheme)
        HStack(spacing: 9) {
            Image(systemName: file.kind.feedSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(lookout.accent)
                .frame(width: 22, height: 22)
                .background(lookout.accentSoft, in: .rect(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            Text(verbatim: file.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(file.kind.feedLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(lookout.card, in: .rect(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension FileKind {
    /// The feed's small glyph for a file of this kind.
    var feedSymbol: String {
        switch self {
        case .image: "photo"
        case .screenshot: "camera.viewfinder"
        case .pdf: "doc.richtext"
        case .doc: "doc.text"
        }
    }

    /// The feed's word for this kind: the result chips' words.
    var feedLabel: LocalizedStringResource {
        switch self {
        case .image: .lookoutKindPicture
        case .screenshot: .lookoutKindScreenshot
        case .pdf: .lookoutKindPDF
        case .doc: .lookoutKindDocument
        }
    }
}

#Preview("First pass · dark") {
    LookoutSetupSheetPreview(step: .firstPass)
        .preferredColorScheme(.dark)
}

#Preview("First pass · counting, light, German") {
    LookoutSetupFirstPassStep(progress: LookoutFirstPassProgress(status: nil), current: nil)
        .padding(EdgeInsets(top: 28, leading: 34, bottom: 10, trailing: 34))
        .frame(width: 640)
        .background(.regularMaterial)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "de"))
}
