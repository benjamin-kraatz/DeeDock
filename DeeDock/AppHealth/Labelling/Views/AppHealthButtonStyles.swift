import SwiftUI

/// The answer and detail buttons of a labelling question: quiet rounded tiles on the glass that lift on hover and
/// settle on press, the way Control Center's tiles do. All of them look alike on purpose: a more prominent
/// button would nudge people toward it and bias the labels.
///
/// Press feedback is a small scale with a spring; Reduce Motion keeps the colour change and drops the scale.
struct AppHealthChoiceButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        AppHealthChoiceButtonBody(configuration: configuration, reduceMotion: reduceMotion)
    }
}

private struct AppHealthChoiceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let reduceMotion: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background {
                Self.shape.fill(.quaternary)
                Self.shape.fill(.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.05 : 0))
            }
            .overlay { Self.shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
            .contentShape(Self.shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// The small "…" and close buttons in a question's corner: a glyph that gains a round backdrop on hover and
/// shrinks a touch on press.
struct AppHealthIconButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        AppHealthIconButtonBody(configuration: configuration, reduceMotion: reduceMotion)
    }
}

private struct AppHealthIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let reduceMotion: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering || configuration.isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: 22, height: 22)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0), in: .circle)
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

#if DEBUG
#Preview("Button styles") {
    VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
            Button("Expected") {}
            Button("Misbehaving") {}
            Button("Not sure") {}
        }
        .buttonStyle(AppHealthChoiceButtonStyle(reduceMotion: false))
        HStack(spacing: 2) {
            Button { } label: { Image(systemName: "ellipsis") }
            Button { } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
        }
        .buttonStyle(AppHealthIconButtonStyle(reduceMotion: false))
    }
    .padding(16)
    .appHealthSurface(opaque: false)
    .padding()
}
#endif
