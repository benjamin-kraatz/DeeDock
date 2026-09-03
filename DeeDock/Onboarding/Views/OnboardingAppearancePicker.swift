import SwiftUI

/// A dock wearing six running indicators at once, one per icon. Click the one you like.
///
/// The alternative — a row of chips under a preview — is the control Settings already has, and
/// it asks a person to map a label onto a mark they cannot see yet. Here every option is drawn
/// at full size and choosing one is a click on the thing itself.
///
/// A style is two pieces of artwork: `DockIconIndicator` treats the icon square, and
/// `DockRunningIndicator` draws the separate mark beside it. Most of the gallery — neon, aura,
/// orbit, prism — lives entirely in the first, so both have to be applied here exactly as
/// `DockSampleView` applies them, or those options render as nothing at all.
struct OnboardingAppearancePicker: View {
    /// The style currently saved, always present in the gallery so the choice is visible.
    let style: DockSettings.RunningIndicatorStyle
    var select: (DockSettings.RunningIndicatorStyle) -> Void = { _ in }
    /// Previews pass an explicit value; the picker otherwise follows the system setting.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered: DockSettings.RunningIndicatorStyle?

    /// A spread across the gallery rather than all fifteen, which at this size would read as
    /// noise. The saved style is prepended so a person always sees which one is theirs.
    private static let gallery: [DockSettings.RunningIndicatorStyle] = [.dot, .bar, .neon, .aura, .orbit, .prism]

    private var styles: [DockSettings.RunningIndicatorStyle] {
        var result = [style]
        for candidate in Self.gallery where !result.contains(candidate) && result.count < Self.gallery.count {
            result.append(candidate)
        }
        return result
    }

    private static let symbols = ["safari", "envelope.fill", "music.note", "camera.fill", "terminal.fill", "gearshape.fill"]
    private static let colors: [Color] = [.blue, .cyan, .pink, .orange, .gray, .indigo]
    private static let iconSize: CGFloat = 54
    private static let spacing: CGFloat = 14

    var body: some View {
        let styles = styles
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(styles.indices, id: \.self) { index in
                option(styles[index], index: index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background {
            // The same glass the dock uses, so the gallery is a dock rather than a swatch board.
            DockBackgroundView(reduceTransparency: reduceTransparency, idleOpacity: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.onboardingAppearancePickerLabel))
    }

    private func option(_ candidate: DockSettings.RunningIndicatorStyle, index: Int) -> some View {
        let isSelected = candidate == style
        let isHovered = hovered == candidate
        return Button { select(candidate) } label: {
            VStack(spacing: DockGeometry.indicatorSpacing) {
                RoundedRectangle(cornerRadius: Self.iconSize * 0.23, style: .continuous)
                    .fill(Self.colors[index % Self.colors.count].gradient)
                    .overlay {
                        Image(systemName: Self.symbols[index % Self.symbols.count])
                            .font(.system(size: Self.iconSize * 0.44, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .modifier(DockIconIndicator(style: candidate, running: true, size: Self.iconSize))
                    .overlay {
                        // Outside the icon square, so it never competes with a style that draws
                        // its own border, such as neon or aura.
                        RoundedRectangle(cornerRadius: Self.iconSize * 0.3, style: .continuous)
                            .strokeBorder(.white, lineWidth: 2)
                            .padding(-5)
                            .opacity(isSelected ? 1 : 0)
                    }
                    // Lifting on hover is the dock's own idiom for "this responds to you".
                    .offset(y: isHovered && !reduceMotion ? -5 : 0)
                    .shadow(color: .black.opacity(isSelected ? 0.3 : 0), radius: 5, y: 2)
                DockRunningIndicator(style: candidate, edge: .bottom)
                    .frame(height: DockGeometry.indicatorSize)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovered = $0 ? candidate : (hovered == candidate ? nil : hovered) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isHovered)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isSelected)
        .accessibilityLabel(Text(candidate.indicatorLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension DockSettings.RunningIndicatorStyle {
    /// Spoken name for a gallery entry, taken from the Appearance pane's own option list rather
    /// than a second set of strings that could drift away from it.
    var indicatorLabel: LocalizedStringResource {
        Self.settingsOptions.first { $0.value == self }?.title ?? .settingsIndicatorDot
    }
}

#if DEBUG
private struct AppearancePickerHarness: View {
    @State private var style: DockSettings.RunningIndicatorStyle = .dot
    var body: some View {
        OnboardingStage(tint: OnboardingStep.appearance.tint) {
            OnboardingAppearancePicker(style: style, select: { style = $0 })
        }
        .padding(28).frame(width: 700)
    }
}

#Preview("Appearance picker") { AppearancePickerHarness() }

#Preview("Appearance picker — a style outside the gallery is still shown") {
    OnboardingStage(tint: OnboardingStep.appearance.tint) {
        OnboardingAppearancePicker(style: .hologram)
    }
    .padding(28).frame(width: 700).preferredColorScheme(.dark)
}
#endif
