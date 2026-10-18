import SwiftUI

/// The island colour behind a tile, for running indicators that take the island's tint.
/// Nil outside islands, where indicators keep their neutral colour.
private struct DockIslandTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var dockIslandTint: Color? {
        get { self[DockIslandTintKey.self] }
        set { self[DockIslandTintKey.self] = newValue }
    }
}

extension DockIslandColor {
    /// A SwiftUI colour at the given brightness. The accent colour ignores `brightness`.
    func color(brightness: Double, opacity: Double = 1) -> Color {
        if isAccent { return Color.accentColor.opacity(opacity) }
        return Color(hue: hue / 360, saturation: saturation, brightness: brightness, opacity: opacity)
    }
}

extension DockIslandPresentation {
    /// The resolved colour of the island covering `slotIndex`.
    func color(forSlot slotIndex: Int) -> DockIslandColor? {
        guard let index = spans.firstIndex(where: { $0.range.contains(slotIndex) }), index < colors.count else { return nil }
        return colors[index]
    }
}
