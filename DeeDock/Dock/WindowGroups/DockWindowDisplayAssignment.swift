import CoreGraphics

/// Both inputs use Quartz global points, including negative origins. A spanning window
/// belongs to the display with the largest overlap; the lowest runtime ID breaks ties.
nonisolated enum DockWindowDisplayAssignment {
    static func display(for window: CGRect, among displays: [UInt32: CGRect]) -> UInt32? {
        var result: UInt32?
        var largestArea: CGFloat = 0
        for id in displays.keys.sorted() {
            guard let frame = displays[id] else { continue }
            let overlap = window.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largestArea { result = id; largestArea = area }
        }
        return result
    }
}
