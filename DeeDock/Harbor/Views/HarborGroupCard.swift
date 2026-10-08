import SwiftUI

/// The card behind one app's windows: header with icon, name, and window count, and the glow
/// that marks the group holding the pointer or the keyboard selection.
///
/// Thumbnails, captions, and chips are drawn by ``HarborView`` above the card, so they can fly
/// independently of it.
struct HarborGroupCard: View {
    let name: String
    let count: Int
    let icon: NSImage?
    let highlighted: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        if reduceTransparency {
            return colorScheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.17) : Color(red: 0.94, green: 0.94, blue: 0.95)
        }
        return colorScheme == .dark ? Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.5) : Color.white.opacity(0.46)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: HarborStyle.groupCornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: HarborStyle.groupCornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.09), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 25, y: 18)
                .background {
                    // Behind the card and cut out inside it, so the halo never tints the glass.
                    HarborGlowBorder(cornerRadius: HarborStyle.groupCornerRadius, reduceMotion: reduceMotion)
                        .opacity(highlighted ? 1 : 0)
                        .animation(.easeInOut(duration: 0.35), value: highlighted)
                }
            HarborGroupHeader(name: name, count: count, icon: icon)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
    }
}

/// Icon, app name, and window count at the top of a group card.
struct HarborGroupHeader: View {
    let name: String
    let count: Int
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
            }
            Text(verbatim: name)
                .font(.system(size: 16, weight: .semibold))
            Text(verbatim: "· " + String(localized: .harborWindowCount(count)))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(height: 26)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A spectrum ring around the highlighted group, as in the mockup: a thin band on the card's
/// edge and a soft halo outside it. The halo is punched out inside the card so the translucent
/// glass keeps its own color. The ring slowly turns; Reduce Motion holds it still.
struct HarborGlowBorder: View {
    let cornerRadius: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let reach = HarborStyle.glowReach
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = reduceMotion ? 0
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: HarborStyle.glowPeriod)
                    / HarborStyle.glowPeriod
            let gradient = AngularGradient(colors: HarborStyle.glowColors, center: .center, angle: .degrees(turn * 360))
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius + reach, style: .continuous)
                    .strokeBorder(gradient, lineWidth: reach)
                    .padding(-reach)
                    .blur(radius: 14)
                    .opacity(0.7)
                RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 2)
                    .padding(-2)
                // Cut the card's interior out of the halo; `destinationOut` erases what is below.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Group card states") {
    HStack(spacing: 40) {
        HarborGroupCard(name: "Safari", count: 5, icon: nil, highlighted: true, reduceMotion: false, reduceTransparency: false)
            .frame(width: 320, height: 200)
        HarborGroupCard(name: "Vorschau", count: 2, icon: nil, highlighted: false, reduceMotion: false, reduceTransparency: true)
            .frame(width: 260, height: 200)
    }
    .padding(40)
    .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}

#Preview("Group card, light") {
    HarborGroupCard(name: "Finder", count: 1, icon: nil, highlighted: true, reduceMotion: true, reduceTransparency: false)
        .frame(width: 300, height: 180)
        .padding(40)
        .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
        .preferredColorScheme(.light)
}
#endif
