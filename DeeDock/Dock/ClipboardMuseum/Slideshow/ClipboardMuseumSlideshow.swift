import SwiftUI

/// A dark gallery that walks through exhibits one at a time.
///
/// Slides cross-dissolve with a slight directional drift and settle-in scale, and each piece
/// breathes forward slowly while it hangs. Reduce Motion keeps only the dissolve. Arrow keys step,
/// Space pauses, Escape leaves. Controls fade out after the pointer rests.
struct ClipboardMuseumSlideshow: View {
    let exhibits: [ClipboardExhibit]
    let imageURL: (ClipboardExhibit) -> URL?
    let close: () -> Void

    @State private var index: Int
    @State private var direction: CGFloat = 1
    @State private var playing = true
    @State private var chromeVisible = true
    @State private var pointerTick = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds each piece hangs before the next.
    private static let dwell: Double = 7

    init(exhibits: [ClipboardExhibit], startIndex: Int, imageURL: @escaping (ClipboardExhibit) -> URL?,
         close: @escaping () -> Void) {
        self.exhibits = exhibits
        self.imageURL = imageURL
        self.close = close
        _index = State(initialValue: exhibits.indices.contains(startIndex) ? startIndex : 0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.30, green: 0.25, blue: 0.18).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.5, y: 0.0), startRadius: 40, endRadius: 900)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if exhibits.indices.contains(index) {
                ClipboardSlide(exhibit: exhibits[index], imageURL: imageURL(exhibits[index]),
                               breathes: !reduceMotion, dwell: Self.dwell)
                    .id(exhibits[index].id)
                    .transition(slideTransition)
            }
            VStack {
                Spacer()
                ClipboardSlideshowControls(position: index + 1, count: exhibits.count, playing: playing,
                                           previous: { step(-1) }, togglePlay: { playing.toggle() },
                                           next: { step(1) }, close: close)
                    .padding(.bottom, 36)
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(chromeVisible)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.6) : .smooth(duration: 1.2), value: index)
        .animation(.easeInOut(duration: 0.45), value: chromeVisible)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.space) { playing.toggle(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onContinuousHover { _ in
            chromeVisible = true
            pointerTick &+= 1
        }
        .task(id: SlideTimer(index: index, playing: playing)) {
            guard playing, exhibits.count > 1 else { return }
            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled else { return }
            step(1)
        }
        .task(id: pointerTick) {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            chromeVisible = false
        }
        .environment(\.colorScheme, .dark)
    }

    private var slideTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.04)).combined(with: .offset(x: 60 * direction)),
            removal: .opacity.combined(with: .scale(scale: 0.97)).combined(with: .offset(x: -60 * direction)))
    }

    private func step(_ delta: Int) {
        guard !exhibits.isEmpty else { return }
        direction = delta >= 0 ? 1 : -1
        index = (index + delta + exhibits.count) % exhibits.count
    }
}

private struct SlideTimer: Hashable {
    let index: Int
    let playing: Bool
}

/// One hung piece with its caption. The slow forward drift is a single linear animation per slide,
/// started on appear, so it costs nothing between frames the system does not already draw.
private struct ClipboardSlide: View {
    let exhibit: ClipboardExhibit
    let imageURL: URL?
    let breathes: Bool
    let dwell: Double
    @State private var drift = false

    var body: some View {
        VStack(spacing: 40) {
            ClipboardExhibitFrame {
                ClipboardExhibitArtwork(exhibit: exhibit, imageURL: imageURL,
                                        maxSize: CGSize(width: 1_100, height: 620))
            }
            .scaleEffect(drift ? 1.035 : 1)
            VStack(spacing: 8) {
                exhibit.titleText
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Text(.clipboardMuseumCatalogNumber(exhibit.catalogNumber)).monospacedDigit()
                    Text(verbatim: "·")
                    Text(exhibit.medium)
                    Text(verbatim: "·")
                    Text(exhibit.acquiredAt, format: .dateTime.day().month().hour().minute())
                }
                .font(.callout.weight(.medium))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
                if let note = exhibit.curatorNote {
                    Text(verbatim: note)
                        .font(.system(.title3, design: .serif).italic())
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }
            }
        }
        .padding(64)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard breathes else { return }
            withAnimation(.linear(duration: dwell + 1.5)) { drift = true }
        }
    }
}

/// A floating pill of transport controls, drawn solid so it reads over any piece.
private struct ClipboardSlideshowControls: View {
    let position: Int
    let count: Int
    let playing: Bool
    let previous: () -> Void
    let togglePlay: () -> Void
    let next: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            control("backward.fill", .clipboardMuseumSlideshowPrevious, action: previous)
            control(playing ? "pause.fill" : "play.fill",
                    playing ? .clipboardMuseumSlideshowPause : .clipboardMuseumSlideshowPlay, action: togglePlay)
            control("forward.fill", .clipboardMuseumSlideshowNext, action: next)
            Text(.clipboardMuseumSlideshowPosition(position, count))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            Divider().frame(height: 18).overlay(Color.white.opacity(0.25))
            control("xmark", .clipboardMuseumSlideshowClose, action: close)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.62), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
    }

    private func control(_ symbol: String, _ label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}

#if DEBUG
#Preview("Slideshow") {
    ClipboardMuseumSlideshow(exhibits: ClipboardExhibit.previewCollection.filter { !$0.isRedacted }, startIndex: 0,
                             imageURL: { _ in nil }, close: {})
        .frame(width: 1_200, height: 800)
}
#endif
