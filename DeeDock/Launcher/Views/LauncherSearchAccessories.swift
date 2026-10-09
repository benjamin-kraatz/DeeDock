import SwiftUI

/// Marks Robi's answer as the scope of the results. The whole chip is the way back to app search.
struct LauncherRobiScopeChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 5) {
                Image(systemName: hovering ? "xmark" : "sparkles")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14)
                Text(.launcherRobiScope)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(LauncherRobiTint.label(colorScheme))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LauncherRobiTint.fill(hovering: hovering), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(Text(.launcherRobiScopeHelp))
        .accessibilityLabel(Text(.launcherTextSearch))
    }
}

/// Round, hover-lit chrome for the Apps tab's small icon buttons (options menu).
struct LauncherSearchAccessoryButtonStyle: ButtonStyle {
    /// Tints the icon and keeps a wash behind it, marking a non-default state.
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        LauncherSearchAccessory(isPressed: configuration.isPressed, active: active) {
            configuration.label
        }
    }
}

/// Shared hover and press treatment for accessory buttons and the overflow menu label.
struct LauncherSearchAccessory<Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false
    var isPressed = false
    var active = false
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.body.weight(.medium))
            .imageScale(.medium)
            .foregroundStyle(foreground)
            .frame(width: 26, height: 26)
            .background(background, in: .circle)
            .contentShape(.circle)
            .onHover { hovering = $0 }
            .animation(.snappy(duration: 0.15), value: hovering)
    }

    private var foreground: AnyShapeStyle {
        if active { return AnyShapeStyle(LauncherRobiTint.label(colorScheme)) }
        return hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    private var background: AnyShapeStyle {
        if active { return AnyShapeStyle(LauncherRobiTint.fill(pressed: isPressed, hovering: hovering)) }
        return AnyShapeStyle(.primary.opacity(isPressed ? 0.12 : hovering ? 0.07 : 0))
    }
}
