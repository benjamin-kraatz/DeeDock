import SwiftUI

/// Lookout's colors from the approved mockup (`docs/mockups/lookout.html`, `--look`, `--lookSoft`, `--mark`,
/// `--markFg`, `--card2`), for light and dark. Everything else comes from `HubFilesTheme`.
struct LookoutTheme {
    let scheme: ColorScheme

    init(_ scheme: ColorScheme) { self.scheme = scheme }

    private var isDark: Bool { scheme == .dark }

    /// The Lookout accent: section title and glyph, meaning chips, the progress bar. A light cyan on dark and a deep
    /// teal on light, both readable as text.
    var accent: Color {
        isDark ? Color(red: 100 / 255, green: 210 / 255, blue: 1) : Color(red: 0, green: 113 / 255, blue: 164 / 255)
    }
    /// The accent's soft fill behind chips and the promo glyph.
    var accentSoft: Color {
        isDark ? Color(red: 100 / 255, green: 210 / 255, blue: 1).opacity(0.14)
            : Color(red: 0, green: 122 / 255, blue: 180 / 255).opacity(0.10)
    }
    /// The highlight behind matched words, and the "Exact words" chip's fill.
    var mark: Color {
        isDark ? Color(red: 1, green: 214 / 255, blue: 10 / 255).opacity(0.28)
            : Color(red: 1, green: 204 / 255, blue: 0).opacity(0.32)
    }
    /// The "Exact words" chip's text.
    var markText: Color {
        isDark ? Color(red: 1, green: 226 / 255, blue: 122 / 255) : Color(red: 107 / 255, green: 78 / 255, blue: 0)
    }
    /// Cards (promo, honest empty state, "why it matched") over the Hub's glass.
    var card: Color { isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.5) }
    /// The stronger hairline around the promo card and thumbnails (`--line2`).
    var strongLine: Color { isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12) }

    /// The status dot's colors.
    static let ready = Color(red: 50 / 255, green: 215 / 255, blue: 75 / 255)
    static let paused = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let failed = Color(red: 1, green: 69 / 255, blue: 58 / 255)
}

/// The arrival of a Lookout row: a staggered rise (the mockup's `.enter`: 0.38 s, `cubic-bezier(.2,.9,.25,1)`, 6 pt),
/// or a plain 0.2 s fade under Reduce Motion. A row keeps its identity (its path) across the keyword-only and the
/// final results, so only rows that are new rise; the ones already shown stay put.
struct LookoutArrival: ViewModifier {
    /// The row's position in its group, for the 45 ms stagger.
    let index: Int
    let reduceMotion: Bool

    @State private var arrived = false

    static let stagger = 0.045
    static let rise = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.38)

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 6)
            .onAppear {
                guard !arrived else { return }
                let animation = reduceMotion ? Animation.easeOut(duration: 0.2)
                    : Self.rise.delay(Double(min(index, 12)) * Self.stagger)
                withAnimation(animation) { arrived = true }
            }
    }
}

extension View {
    /// Rises in as the `index`th Lookout row (see `LookoutArrival`).
    func lookoutArrival(index: Int, reduceMotion: Bool) -> some View {
        modifier(LookoutArrival(index: index, reduceMotion: reduceMotion))
    }
}
