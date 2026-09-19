import SwiftUI

/// Finder-like capsule shared by related controls, rather than a bezel around every button.
struct AppMeltToolbarGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .font(.system(size: 17, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .padding(3)
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(nsColor: .controlBackgroundColor))
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5) }
                } else {
                    Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                }
            }
    }
}

/// Active and hovered items receive a quiet inset fill inside the shared capsule.
struct AppMeltToolbarButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(isEnabled ? 0.95 : 0.3))
            .background {
                Capsule().fill(.primary.opacity(isEnabled ? fillOpacity(pressed: configuration.isPressed) : 0))
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }

    private func fillOpacity(pressed: Bool) -> Double {
        if pressed { return 0.2 }
        if selected { return 0.13 }
        return hovering ? 0.08 : 0
    }
}

#if DEBUG
#Preview("Toolbar capsules") {
    HStack(spacing: 10) {
        AppMeltToolbarGroup {
            Button {} label: { Image(systemName: "sparkles").frame(width: 38, height: 32) }
                .buttonStyle(AppMeltToolbarButtonStyle())
            Button {} label: { Image(systemName: "arrow.left.arrow.right").frame(width: 38, height: 32) }
                .buttonStyle(AppMeltToolbarButtonStyle(selected: true))
        }
        AppMeltToolbarGroup {
            Button {} label: { Image(systemName: "ellipsis").frame(width: 38, height: 32) }
                .buttonStyle(AppMeltToolbarButtonStyle()).disabled(true)
        }
    }
    .padding(20)
}
#endif
