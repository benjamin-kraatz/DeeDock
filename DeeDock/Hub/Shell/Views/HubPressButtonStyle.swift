import SwiftUI

/// Press feedback for the Hub's custom buttons: the label settles toward `scale` while the mouse
/// is down and springs back on release, the way dock tiles and Finder's toolbar items give way
/// under a click. The label draws exactly as the button built it; nothing else changes.
///
/// Reduce Motion skips the scale, so a press shows no movement.
struct HubPressButtonStyle: ButtonStyle {
    /// The pressed scale. Small controls use a deeper press than large cards.
    var scale: CGFloat = 0.96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(HubStyle.hover, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HubPressButtonStyle {
    /// ``HubPressButtonStyle`` with the default scale.
    static var hubPress: HubPressButtonStyle { HubPressButtonStyle() }

    /// ``HubPressButtonStyle`` with a custom pressed scale.
    static func hubPress(scale: CGFloat) -> HubPressButtonStyle { HubPressButtonStyle(scale: scale) }
}

#Preview("Press feedback") {
    HStack(spacing: 24) {
        Button {} label: {
            Text("Card")
                .padding(20)
                .background(.quaternary, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.hubPress(scale: 0.98))
        Button {} label: {
            Image(systemName: "xmark")
                .frame(width: 32, height: 32)
                .background(.quaternary, in: .rect(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.hubPress(scale: 0.9))
    }
    .padding(32)
}
