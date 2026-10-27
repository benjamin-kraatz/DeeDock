import SwiftUI

/// A suggestion pill: translucent white on light title bars, graphite on dark ones. Hover lifts
/// and brightens it; a press settles it back; disabled pills fade while the context is still read.
///
/// The rim is a half-point-larger capsule under the fill rather than a stroke: a stroked capsule
/// beside a shadow leaves hairlines at the pill's ends on macOS.
struct RobiPillStyle: ButtonStyle {
    let dark: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        RobiPill(configuration: configuration, dark: dark, reduceMotion: reduceMotion)
    }
}

private struct RobiPill: View {
    let configuration: ButtonStyleConfiguration
    let dark: Bool
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var fill: Color {
        dark ? Color(red: 0.17, green: 0.18, blue: 0.22).opacity(hovering ? 0.97 : 0.86)
             : Color.white.opacity(hovering ? 0.98 : 0.86)
    }

    private var rim: Color {
        dark ? Color.white.opacity(hovering ? 0.2 : 0.12) : Color.black.opacity(hovering ? 0.1 : 0.08)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(dark ? Color(white: 0.92) : Color(red: 0.16, green: 0.15, blue: 0.22))
            .background {
                Capsule().fill(rim).padding(-0.5)
                    .shadow(color: .black.opacity(dark ? 0.3 : 0.12), radius: hovering ? 6 : 4, y: hovering ? 3 : 2)
                Capsule().fill(fill)
            }
            .contentShape(Capsule())
            .offset(y: hovering && !configuration.isPressed && !reduceMotion ? -1 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(RobiMotion.feedback(reduceMotion), value: hovering)
            .animation(RobiMotion.feedback(reduceMotion), value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
    }
}

/// The accent-filled button for the one action a notice leads with, such as using a pasted API
/// key. The Run button has its own chip, `RobiRunChipStyle`, which stays lit while disabled for
/// the run and recolours with the result.
///
/// Not `.borderedProminent`: Robi's panel belongs to an app that is never active, and AppKit
/// draws prominent buttons grey in windows that are not key in the active app.
struct RobiProminentButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        RobiProminentButton(configuration: configuration, reduceMotion: reduceMotion)
    }
}

private struct RobiProminentButton: View {
    let configuration: ButtonStyleConfiguration
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : hovering ? 0.92 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(RobiMotion.feedback(reduceMotion), value: hovering)
            .animation(RobiMotion.feedback(reduceMotion), value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
    }
}

#if DEBUG
#Preview("Button styles") {
    VStack(spacing: 16) {
        HStack {
            Button {} label: { Label { Text(.robiSuggestExplain) } icon: { Image(systemName: "questionmark.bubble") } }
                .buttonStyle(RobiPillStyle(dark: false, reduceMotion: false))
            Button {} label: { Label { Text(.robiSuggestExplain) } icon: { Image(systemName: "questionmark.bubble") } }
                .buttonStyle(RobiPillStyle(dark: false, reduceMotion: false))
                .disabled(true)
        }
        .padding(16)
        .background(Color(red: 0.86, green: 0.83, blue: 0.95))
        HStack {
            Button {} label: { Label { Text(.robiSuggestSummarize) } icon: { Image(systemName: "text.alignleft") } }
                .buttonStyle(RobiPillStyle(dark: true, reduceMotion: false))
            Button {} label: { Text(.robiKeyUse) }
                .buttonStyle(RobiProminentButtonStyle(reduceMotion: false))
            Button {} label: { Text(.robiKeyUse) }
                .buttonStyle(RobiProminentButtonStyle(reduceMotion: false))
                .disabled(true)
        }
        .padding(16)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }
    .padding()
}
#endif
