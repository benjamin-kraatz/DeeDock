import AppKit

/// Shared-frame geometry in global AX points. AppKit conversion always uses the primary display,
/// not the screen containing the pair, so negative and vertically arranged displays work.
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
}

extension AppMeltGeometry {
    static var displays: [WindowActionDisplay] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return WindowActionDisplay(id: String(id), runtimeID: id, name: screen.localizedName,
                frame: appKit(screen.frame, primaryTop: primary.frame.maxY),
                usable: appKit(screen.visibleFrame, primaryTop: primary.frame.maxY))
        }
    }
}
