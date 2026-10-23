import SwiftUI
import UniformTypeIdentifiers

/// A plugin tile's picture: its app's icon, like any other tile, greyed out with a restart chip
/// while the plugin is stopped.
///
/// The grey and the chip come and go with a short fade; Reduce Motion swaps them instantly.
struct DockPluginTileArtwork: View {
    let icon: NSImage
    let stopped: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .saturation(stopped ? 0 : 1)
            .opacity(stopped ? 0.42 : 1)
            .overlay(alignment: .bottomTrailing) {
                if stopped {
                    // The chip sits 0.4× the icon wide, hanging just past the icon's bottom-right
                    // corner (6% right, 4% down), so it reads as a mark on the icon, not a badge.
                    DockPluginRestartChip(diameter: size * 0.4)
                        .offset(x: size * 0.06, y: size * 0.04)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: stopped)
    }
}

/// The small round mark on a stopped plugin's tile. The restart itself lives in the tile's menu
/// and the panel; the chip only says one is needed.
///
/// Drawn on menu-like material with a hairline and a soft shadow, so it stands off the greyed
/// icon whatever is behind the dock. Reduce Transparency fills it solid.
struct DockPluginRestartChip: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: diameter * 0.5, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background {
                if reduceTransparency {
                    Circle().fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    Circle().fill(.thickMaterial)
                }
            }
            .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Running and stopped") {
    let icon = NSWorkspace.shared.icon(for: .applicationBundle)
    HStack(spacing: 24) {
        DockPluginTileArtwork(icon: icon, stopped: false, size: 48).frame(width: 48, height: 48)
        DockPluginTileArtwork(icon: icon, stopped: true, size: 48).frame(width: 48, height: 48)
        DockPluginTileArtwork(icon: icon, stopped: true, size: 72).frame(width: 72, height: 72)
    }
    .padding(30)
}

#Preview("Stopped, dark") {
    DockPluginTileArtwork(icon: NSWorkspace.shared.icon(for: .applicationBundle), stopped: true, size: 64)
        .frame(width: 64, height: 64)
        .padding(30)
        .preferredColorScheme(.dark)
}

#Preview("Stopped, toggling") {
    @Previewable @State var stopped = true
    VStack(spacing: 20) {
        DockPluginTileArtwork(icon: NSWorkspace.shared.icon(for: .applicationBundle), stopped: stopped, size: 64)
            .frame(width: 64, height: 64)
        Button(String("Toggle")) { stopped.toggle() }
    }
    .padding(30)
}
#endif
