import Foundation

/// Shared opacity calculation for live docks and inert Settings samples.
struct DockAppearanceOpacity {
    let background: Double
    let icons: Double

    init(settings: DockSettings, idleFraction: Double, reduceTransparency: Bool) {
        let fraction = settings.fadeWhenIdle && !reduceTransparency ? min(1, max(0, idleFraction)) : 0
        let idle = 1 - fraction * (1 - settings.idleOpacity / 100)
        // Native glass has no material-opacity control. Keep its normal appearance intact;
        // the retained legacy preference must not permanently fade its backdrop and highlights.
        let normalBackground = settings.showBackground ? 1.0 : 0.0
        background = normalBackground * (settings.fadeTarget == .iconsOnly ? 1 : idle)
        icons = settings.fadeTarget == .backgroundOnly ? 1 : idle
    }
}
