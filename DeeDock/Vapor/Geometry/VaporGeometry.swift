import CoreGraphics
import Foundation

/// Placement math for the orb and the windows around it. Every input and output frame is in
/// AppKit global coordinates (y up) unless a property says otherwise; nothing here assumes the
/// primary display starts at the origin or that origins are positive.
nonisolated enum VaporGeometry {
    /// The orb's diameter in points.
    static let orbDiameter: CGFloat = 112
    /// Transparent margin around the orb inside its window, for the badge, squash and glow.
    static let orbCanvasInset: CGFloat = 36
    /// Keeps the orb this far inside its display's visible frame.
    static let screenMargin: CGFloat = 8
    /// Space between the orb's edge and the panel.
    static let panelGap: CGFloat = 18
    /// The panel's inset from the visible frame's edges.
    static let panelMargin: CGFloat = 12
    /// A suggestion bubble's diameter.
    static let bubbleDiameter: CGFloat = 38
    /// The angle between neighbouring bubbles on their arc, in radians.
    static let bubbleStep: Double = 0.4
    /// How many suggestion bubbles float beside the orb at most.
    static let maxBubbles = 5

    static var orbWindowSize: CGSize {
        let side = orbDiameter + orbCanvasInset * 2
        return CGSize(width: side, height: side)
    }

    /// The orb window's frame for an orb centred at `center`.
    static func orbWindowFrame(center: CGPoint) -> CGRect {
        let size = orbWindowSize
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: Placement

    /// Moves `center` so the whole orb (not its transparent canvas) sits inside `visibleFrame`.
    static func clampedCenter(_ center: CGPoint, in visibleFrame: CGRect) -> CGPoint {
        let inset = orbDiameter / 2 + screenMargin
        let area = visibleFrame.insetBy(dx: inset, dy: inset)
        guard area.width >= 0, area.height >= 0 else { return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY) }
        return CGPoint(x: min(max(center.x, area.minX), area.maxX), y: min(max(center.y, area.minY), area.maxY))
    }

    /// The relative placement stored for an orb centred at `center` on a display.
    static func placement(center: CGPoint, in visibleFrame: CGRect) -> VaporOrbPlacement {
        let clamped = clampedCenter(center, in: visibleFrame)
        let width = max(visibleFrame.width, 1), height = max(visibleFrame.height, 1)
        return VaporOrbPlacement(x: Double((clamped.x - visibleFrame.minX) / width),
                                 y: Double((clamped.y - visibleFrame.minY) / height))
    }

    /// The orb centre for a stored placement, clamped into the display's current visible frame.
    static func center(for placement: VaporOrbPlacement, in visibleFrame: CGRect) -> CGPoint {
        clampedCenter(CGPoint(x: visibleFrame.minX + CGFloat(placement.x) * visibleFrame.width,
                              y: visibleFrame.minY + CGFloat(placement.y) * visibleFrame.height), in: visibleFrame)
    }

    /// Where a first-time orb appears: near the right edge, a third of the way up.
    static func defaultCenter(in visibleFrame: CGRect) -> CGPoint {
        clampedCenter(CGPoint(x: visibleFrame.maxX - orbDiameter, y: visibleFrame.minY + visibleFrame.height * 0.32),
                      in: visibleFrame)
    }

    /// The display and centre the orb should use now.
    ///
    /// The saved display wins while it's connected. Otherwise the orb goes to the primary display,
    /// at that display's own saved placement or the default. The fallback is not written back, so
    /// the orb returns when its display is plugged in again.
    static func resolve(_ state: VaporPersistedState, displays: [VaporDisplay]) -> (display: VaporDisplay, center: CGPoint)? {
        guard let display = displays.first(where: { $0.id == state.displayID })
            ?? displays.first(where: \.isPrimary) ?? displays.first else { return nil }
        let center = state.placements[display.id].map { self.center(for: $0, in: display.visibleFrame) }
            ?? defaultCenter(in: display.visibleFrame)
        return (display, center)
    }

    /// The display under `point`, or the one whose visible frame is nearest.
    static func display(at point: CGPoint, in displays: [VaporDisplay]) -> VaporDisplay? {
        if let hit = displays.first(where: { $0.frame.contains(point) }) { return hit }
        return displays.min { distance(from: point, to: $0.visibleFrame) < distance(from: point, to: $1.visibleFrame) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    // MARK: Panel and capsules

    /// Whether the orb is on the right half of its display, so things open toward the left.
    static func opensLeft(orbCenter: CGPoint, visibleFrame: CGRect) -> Bool {
        orbCenter.x > visibleFrame.midX
    }

    /// The panel's frame: beside the orb on the side facing the screen centre, its top about
    /// 62 % of its height above the orb's centre, clamped inside the visible frame.
    static func panelFrame(orbCenter: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let area = visibleFrame.insetBy(dx: panelMargin, dy: panelMargin)
        let width = min(size.width, area.width), height = min(size.height, area.height)
        var x = opensLeft(orbCenter: orbCenter, visibleFrame: visibleFrame)
            ? orbCenter.x - orbDiameter / 2 - panelGap - width
            : orbCenter.x + orbDiameter / 2 + panelGap
        x = min(max(x, area.minX), area.maxX - width)
        var y = orbCenter.y - height * 0.38
        y = min(max(y, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The orb's centre as a unit point of `frame` in SwiftUI's y-down space, for a scale
    /// transition that grows a window out of the orb.
    static func anchor(of orbCenter: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: (orbCenter.x - frame.minX) / max(frame.width, 1), y: (frame.maxY - orbCenter.y) / max(frame.height, 1))
    }

    /// The undo/freed capsule: centred above the orb, or below it when there's no room above.
    static func statusFrame(orbCenter: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 14
        var y = orbCenter.y + orbDiameter / 2 + gap
        if y + size.height > visibleFrame.maxY - panelMargin { y = orbCenter.y - orbDiameter / 2 - gap - size.height }
        var x = orbCenter.x - size.width / 2
        x = min(max(x, visibleFrame.minX + panelMargin), visibleFrame.maxX - panelMargin - size.width)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: Orb decoration

    /// The badge sits on the top corner facing away from the screen centre, so bubbles, which sit
    /// on the side facing the centre, never cover it.
    static func badgeCorner(orbCenter: CGPoint, visibleFrame: CGRect) -> VaporBadgeCorner {
        opensLeft(orbCenter: orbCenter, visibleFrame: visibleFrame) ? .topTrailing : .topLeading
    }

    /// Lighting from the display's lamp, just above the middle of its top edge.
    ///
    /// Distance is scaled to a 1200 pt-wide reference display before the falloff, so the same
    /// relative spot looks the same on a laptop and a large external display.
    static func lighting(orbCenter: CGPoint, displayFrame: CGRect) -> VaporLighting {
        let lamp = CGPoint(x: displayFrame.midX, y: displayFrame.maxY + 40)
        let dx = Double(lamp.x - orbCenter.x), dy = Double(lamp.y - orbCenter.y)
        let angle = atan2(dx, dy)
        let scale = 1200 / Double(max(displayFrame.width, displayFrame.height, 1))
        let distance = hypot(dx, dy) * scale
        let intensity = min(max(1.25 - distance / 1000, 0.5), 1.15)
        return VaporLighting(angle: angle, intensity: intensity,
                             shadowOffset: CGSize(width: -sin(angle) * Double(orbDiameter) * 0.22, height: 0),
                             shadowStretch: 1 + abs(sin(angle)) * 0.25)
    }

    /// How close a drag at `point` is to an orb centred at `orbCenter`.
    static func dropProximity(point: CGPoint, orbCenter: CGPoint) -> VaporDropProximity {
        let dx = point.x - orbCenter.x, dy = point.y - orbCenter.y
        let distance = hypot(dx, dy), radius = orbDiameter / 2
        let q = min(max(1 - (distance - radius) / 190, 0), 1)
        let value = Double(q * q)
        let unit = distance > 0 ? CGVector(dx: dx / distance, dy: dy / distance) : .zero
        // SwiftUI's y axis points down, so the vertical lean flips.
        return VaporDropProximity(value: value, isOverOrb: distance < radius + 26,
                                  lean: CGSize(width: unit.dx * 7 * value, height: -unit.dy * 7 * value))
    }

    // MARK: Suggestions

    /// The point bubbles and the capsule face: the display's centre, a little above the middle.
    static func suggestionTarget(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + visibleFrame.height * 0.58)
    }

    /// Bubbles on an arc beside the orb, facing the screen centre, and the capsule beyond them.
    ///
    /// - Parameters:
    ///   - count: Bubbles to place; at most ``maxBubbles`` are used.
    ///   - capsuleSize: The capsule's expected size; the window leaves room for it.
    static func satelliteLayout(orbCenter: CGPoint, count: Int, capsuleSize: CGSize,
                                visibleFrame: CGRect) -> VaporSatelliteLayout {
        let target = suggestionTarget(in: visibleFrame)
        let tx = target.x - orbCenter.x, ty = target.y - orbCenter.y
        let length = max(hypot(tx, ty), 1)
        let dir = CGVector(dx: tx / length, dy: ty / length)
        let phi = atan2(Double(dir.dy), Double(dir.dx))
        let rho = Double(orbDiameter / 2 + 32)
        let shown = min(count, maxBubbles)
        let bubbles = (0..<shown).map { index -> CGPoint in
            let angle = phi + (Double(index) - Double(shown - 1) / 2) * bubbleStep
            return CGPoint(x: orbCenter.x + CGFloat(cos(angle) * rho), y: orbCenter.y + CGFloat(sin(angle) * rho))
        }
        let reach = CGFloat(rho) + bubbleDiameter / 2 + 14 + abs(dir.dx) * capsuleSize.width / 2
            + abs(dir.dy) * capsuleSize.height / 2
        let margin: CGFloat = 10
        let capsule = CGPoint(
            x: min(max(orbCenter.x + dir.dx * reach, visibleFrame.minX + capsuleSize.width / 2 + margin),
                   visibleFrame.maxX - capsuleSize.width / 2 - margin),
            y: min(max(orbCenter.y + dir.dy * reach, visibleFrame.minY + capsuleSize.height / 2 + margin),
                   visibleFrame.maxY - capsuleSize.height / 2 - margin))
        var bounds = CGRect(x: capsule.x - capsuleSize.width / 2, y: capsule.y - capsuleSize.height / 2,
                            width: capsuleSize.width, height: capsuleSize.height)
        for bubble in bubbles {
            bounds = bounds.union(CGRect(x: bubble.x - bubbleDiameter / 2, y: bubble.y - bubbleDiameter / 2,
                                         width: bubbleDiameter, height: bubbleDiameter))
        }
        let window = bounds.insetBy(dx: -12, dy: -12).integral
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - window.minX, y: window.maxY - point.y) }
        return VaporSatelliteLayout(windowFrame: window, bubbleCenters: bubbles.map(local),
                                    capsuleCenter: local(capsule), orbCenter: local(orbCenter))
    }
}
