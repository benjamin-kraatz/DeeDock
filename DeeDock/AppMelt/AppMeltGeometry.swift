import AppKit

/// Shared-frame geometry in global AX points. Quartz and AX share a top-left origin on the
/// main display (`CGMainDisplayID`, the menu-bar display). AppKit's origin is that display's
/// bottom-left. The flip axis is the main display's AppKit `maxY`, including when that
/// display is not `NSScreen.screens.first` and when other displays are taller or stacked.
/// Flipping by the display under the pointer uses the wrong axis in those arrangements.
nonisolated enum AppMeltGeometry {
    static let rim: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let header: CGFloat = 52
    static let divider: CGFloat = 8

    /// Preserve the source group's horizontal center and top content edge, allowing room for
    /// the header. Only screen bounds and native minimum sizes should force displacement.
    static func initialFrame(first: CGRect, second: CGRect, usable: CGRect) -> CGRect {
        let bounds = first.union(second)
        let size = CGSize(width: min(usable.width, max(640, first.width + second.width + rim * 2 + divider)),
                          height: min(usable.height, max(360, max(first.height, second.height) + header + rim)))
        return WindowPlacementPolicy.fit(CGRect(x: bounds.midX - size.width / 2,
            y: bounds.minY - header, width: size.width, height: size.height), into: usable)
    }

    static func windows(in frame: CGRect, ratio: Double) -> [CGRect] {
        let width = frame.width - rim * 2 - divider
        let left = (width * min(0.75, max(0.25, ratio))).rounded()
        let height = frame.height - header - rim
        return [CGRect(x: frame.minX + rim, y: frame.minY + header, width: left, height: height),
                CGRect(x: frame.minX + rim + left + divider, y: frame.minY + header,
                       width: width - left, height: height)]
    }

    static func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
            && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    static func appKit(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func screenID(_ screen: NSScreen) -> UInt32? {
        let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        if let number = value as? NSNumber { return number.uint32Value }
        return value as? UInt32
    }

    /// The menu-bar display. Quartz window bounds and AX positions are measured from its top-left.
    static func mainScreen(among screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let main = CGMainDisplayID()
        return screens.first { screenID($0) == main } ?? screens.first
    }

    static func mainDisplayTop(among screens: [NSScreen] = NSScreen.screens) -> CGFloat {
        mainScreen(among: screens)?.frame.maxY ?? 0
    }

    /// Converts a global AppKit point to the Quartz space used by `CGWindow` bounds.
    /// X is shared. Y is the distance below the main display's top, so a point on a
    /// secondary display keeps that display's global X and its signed Quartz Y.
    static func quartz(fromAppKit point: CGPoint, screens: [NSScreen] = NSScreen.screens) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayTop(among: screens) - point.y)
    }
}

extension AppMeltGeometry {
    static var displays: [WindowActionDisplay] {
        let screens = NSScreen.screens
        guard mainScreen(among: screens) != nil else { return [] }
        let top = mainDisplayTop(among: screens)
        return screens.compactMap { screen in
            guard let id = screenID(screen) else { return nil }
            return WindowActionDisplay(id: String(id), runtimeID: id, name: screen.localizedName,
                frame: appKit(screen.frame, primaryTop: top),
                usable: appKit(screen.visibleFrame, primaryTop: top))
        }
    }
}
