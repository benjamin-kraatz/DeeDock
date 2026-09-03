#if DEBUG
import Foundation
import CoreGraphics

/// In-memory device fixtures; never enumerates displays, opens panels, or writes preferences.
@MainActor
enum DisplaySettingsPreview {
    static func make() -> DisplayProfilesStore {
        let defaults = DockSettingsStore(repository: nil)
        let profiles = DisplayProfilesStore(defaults: defaults, repository: nil)
        let displays = [display(1), display(2), display(3)]
        profiles.synchronize(displays) { [] }
        profiles.update(displays[1].id, keyPath: \.iconSize, to: 64)
        profiles.setEnabled(false, for: displays[2].id)
        profiles.synchronize(Array(displays.prefix(2))) { [] }
        return profiles
    }

    private static func display(_ index: Int) -> DisplaySnapshot {
        let origin = CGFloat(index - 1) * 1600
        let frame = CGRect(x: origin, y: 0, width: 1600, height: 1000)
        let visible = CGRect(x: origin, y: 80, width: 1600, height: 900)
        return DisplaySnapshot(id: "display.preview\(index)", runtimeID: UInt32(index), name: "Sample Display \(index)",
                               isPersistent: true, isPrimary: index == 1, frame: frame, visibleFrame: visible,
                               mirrorSource: nil, isDrawable: true)
    }

}
#endif
