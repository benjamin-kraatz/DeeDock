import SwiftUI

/// The Attach Picture switch at the end of the prompt bar, shown when the whole window is the
/// context. On, a picture of the window goes with every question beside its text; off, Robi
/// takes one only when the window has too little text to read. Disabled without Screen Recording.
///
/// A small round button at the context chip's height: the tab's ink at the chip's strength when
/// off, filled with the accent colour when on. The symbol swaps with the state, so the
/// difference never depends on colour alone.
struct RobiPictureToggle: View {
    let model: RobiModel
    let toggle: () -> Void

    private var isOn: Bool { model.attachesWindowPicture && model.canAttachPicture }

    private var help: LocalizedStringResource {
        if !model.canAttachPicture { return .robiPictureToggleNeedsAccess }
        return isOn ? .robiPictureToggleHelpOn : .robiPictureToggleHelpOff
    }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "photo.fill" : "photo")
                .contentTransition(model.reduceMotion ? .opacity : .symbolEffect(.replace))
        }
        .buttonStyle(RobiPictureToggleStyle(isOn: isOn, ink: model.ink, reduceMotion: model.reduceMotion))
        .disabled(!model.canAttachPicture)
        .help(Text(help))
        .accessibilityLabel(Text(.robiPictureToggleLabel))
        .accessibilityValue(Text(isOn ? .robiPictureToggleOn : .robiPictureToggleOff))
        .accessibilityHint(Text(help))
        .accessibilityAddTraits(.isToggle)
    }
}

/// The switch's round face. Hover deepens the off state's fill and lightens the on state's; a
/// press settles the face back, like Robi's pills. Disabled, it fades like the prominent button.
private struct RobiPictureToggleStyle: ButtonStyle {
    let isOn: Bool
    let ink: Color
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        RobiPictureToggleFace(configuration: configuration, isOn: isOn, ink: ink, reduceMotion: reduceMotion)
    }
}

private struct RobiPictureToggleFace: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    let ink: Color
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    /// The context chip's height, so the two sit on one line with the same rhythm.
    private static let diameter: CGFloat = 22

    private var fill: AnyShapeStyle {
        if isOn { return AnyShapeStyle(Color.accentColor) }
        // Off: the chip's 0.10 of ink at rest, a step deeper under the pointer and the press.
        return AnyShapeStyle(ink.opacity(configuration.isPressed ? 0.2 : hovering ? 0.16 : 0.10))
    }

    /// A touch of white over the accent on hover, and a touch of shade under the press, so the
    /// on state answers the pointer too.
    private var sheen: Color {
        guard isOn else { return .clear }
        if configuration.isPressed { return .black.opacity(0.12) }
        return hovering ? .white.opacity(0.14) : .clear
    }

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : ink.opacity(hovering ? 0.95 : 0.7))
            .frame(width: Self.diameter, height: Self.diameter)
            .background { Circle().fill(fill) }
            .overlay { Circle().fill(sheen) }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(RobiMotion.feedback(reduceMotion), value: hovering)
            .animation(RobiMotion.feedback(reduceMotion), value: configuration.isPressed)
            .animation(RobiMotion.feedback(reduceMotion), value: isOn)
            .onHover { hovering = $0 && isEnabled }
    }
}

#if DEBUG
/// The switch beside the chip it shares a line with: off, on, and without Screen Recording.
private struct RobiPictureTogglePreview: View {
    let dark: Bool

    private func model(on: Bool, allowed: Bool) -> RobiModel {
        let model = RobiPreviewData.model(.prompting, dark: dark, context: RobiPreviewData.window)
        model.attachesWindowPicture = on
        model.canAttachPicture = allowed
        return model
    }

    var body: some View {
        HStack(spacing: 14) {
            RobiContextChip(model: model(on: false, allowed: true))
            RobiPictureToggle(model: model(on: false, allowed: true), toggle: {})
            RobiPictureToggle(model: model(on: true, allowed: true), toggle: {})
            RobiPictureToggle(model: model(on: true, allowed: false), toggle: {})
        }
        .padding(20)
        .background(dark ? RobiPreviewData.darkTint : RobiPreviewData.lightTint)
    }
}

#Preview("Attach Picture: off, on, no Screen Recording (dark)") { RobiPictureTogglePreview(dark: true) }
#Preview("Attach Picture: off, on, no Screen Recording (light)") { RobiPictureTogglePreview(dark: false) }
#endif
