import Foundation

/// Shared opacity calculation for live docks and inert Settings samples.
struct DockAppearanceOpacity {
    let background: Double
    let icons: Double

    init(settings: DockSettings, idleFraction: Double, reduceTransparency: Bool) {
        let fraction = settings.fadeWhenIdle && !reduceTransparency ? min(1, max(0, idleFraction)) : 0
        let idle = 1 - fraction * (1 - settings.idleOpacity / 100)
        let normalBackground = settings.showBackground ? (reduceTransparency ? 1 : settings.backgroundOpacity / 100) : 0
        background = normalBackground * (settings.fadeTarget == .iconsOnly ? 1 : idle)
        icons = settings.fadeTarget == .backgroundOnly ? 1 : idle
    }
}
