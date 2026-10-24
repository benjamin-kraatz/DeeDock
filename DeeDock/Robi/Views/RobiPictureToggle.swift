import SwiftUI

/// The Attach Picture switch at the end of the prompt bar, shown when the whole window is the
/// context. On, a picture of the window goes with every question beside its text; off, Robi
/// takes one only when the window has too little text to read. Disabled without Screen Recording.
///
/// A small round button in the tab's ink: outlined when off, filled with the accent colour when
/// on. The symbol swaps with the state, so the difference never depends on colour alone.
struct RobiPictureToggle: View {
    let model: RobiModel
    let toggle: () -> Void
    @State private var hovering = false

    private var isOn: Bool { model.attachesWindowPicture && model.canAttachPicture }

    private var help: LocalizedStringResource {
        if !model.canAttachPicture { return .robiPictureToggleNeedsAccess }
        return isOn ? .robiPictureToggleHelpOn : .robiPictureToggleHelpOff
    }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "photo.fill" : "photo")
                .font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isOn ? Color.white : model.ink.opacity(hovering ? 0.9 : 0.62))
                .frame(width: 24, height: 22)
                .background {
                    Capsule()
                        .fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(model.ink.opacity(hovering ? 0.14 : 0.08)))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canAttachPicture)
        .opacity(model.canAttachPicture ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(model.reduceMotion ? nil : .snappy(duration: 0.2), value: isOn)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(Text(help))
        .accessibilityLabel(Text(.robiPictureToggleLabel))
        .accessibilityValue(Text(isOn ? .robiPictureToggleOn : .robiPictureToggleOff))
        .accessibilityHint(Text(help))
        .accessibilityAddTraits(.isToggle)
    }
}

#if DEBUG
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
