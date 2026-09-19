import AppKit

/// Quartz geometry only: no screenshots, AX enumeration, or retained foreign UI objects.
nonisolated struct AppMeltVisibleWindow: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

actor AppMeltProximityScanner {
    func snapshot() -> [AppMeltVisibleWindow] {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = row[kCGWindowNumber as String] as? NSNumber,
                  let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 200, frame.height >= 120,
                  ((row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else { return nil }
            return AppMeltVisibleWindow(id: id.uint32Value, pid: pid.int32Value, frame: frame)
        }
    }
}

nonisolated enum AppMeltProximityGeometry {
    /// Neighbouring edges may overlap slightly. Deep overlap is not a melt gesture.
    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat? {
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let horizontalGap = min(abs(a.maxX - b.minX), abs(b.maxX - a.minX))
        let verticalGap = min(abs(a.maxY - b.minY), abs(b.maxY - a.minY))
        var distances: [CGFloat] = []
        if verticalOverlap >= 100, horizontalGap <= 32 { distances.append(horizontalGap) }
        if horizontalOverlap >= 100, verticalGap <= 32 { distances.append(verticalGap) }
        return distances.min()
    }
}
