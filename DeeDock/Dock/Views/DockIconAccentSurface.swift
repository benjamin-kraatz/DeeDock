import AppKit
import SwiftUI

extension DockIconAccent {
    /// The icon's dominant hue, toned for panel surfaces rather than for emitted light.
    ///
    /// `accent(for:identity:)` returns full brightness and high saturation. The same value
    /// behind body text is unreadable on a light window, and a yellow or cyan icon is the
    /// case that proves it. Fixing saturation and brightness per appearance keeps every
    /// app's window equally legible while still being recognizably its color.
    ///
    /// Returns `nil` for achromatic artwork, where the caller should stay on the system accent.
    static func surface(for icon: NSImage, identity: String, dark: Bool) -> Color? {
        guard let accent = accent(for: icon, identity: identity),
              let sRGB = NSColor(accent).usingColorSpace(.sRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        sRGB.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: Double(hue), saturation: dark ? 0.62 : 0.78, brightness: dark ? 0.95 : 0.62)
    }
}

#if DEBUG
#Preview("Surface tints, light and dark") {
    let icons = ["safari", "envelope.fill", "leaf.fill", "flame.fill"]
    return HStack(spacing: 12) {
        ForEach(icons, id: \.self) { symbol in
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
            VStack(spacing: 6) {
                Image(nsImage: icon).frame(width: 32, height: 32)
                ForEach([false, true], id: \.self) { dark in
                    Text(verbatim: "Aa")
                        .foregroundStyle(DockIconAccent.surface(for: icon, identity: symbol, dark: dark) ?? .accentColor)
                        .frame(width: 48, height: 28)
                        .background((dark ? Color.black : .white), in: .rect(cornerRadius: 6))
                }
            }
        }
    }
    .padding()
}
#endif
