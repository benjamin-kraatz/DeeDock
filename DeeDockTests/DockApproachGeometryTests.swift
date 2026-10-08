import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

@MainActor struct DockApproachGeometryTests {
    /// A secondary display left of the primary, so negative origins are exercised.
    private let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)

    private func zone(_ edge: DockEdge) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: -900, y: 0, width: 360, height: 8)
        case .top: CGRect(x: -900, y: 892, width: 360, height: 8)
        case .left: CGRect(x: -1440, y: 270, width: 8, height: 360)
        case .right: CGRect(x: -8, y: 270, width: 8, height: 360)
        }
    }

    /// A point `inward` points from the edge, at the zone's center along the edge.
    private func point(_ edge: DockEdge, inward: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: -720, y: inward)
        case .top: CGPoint(x: -720, y: 900 - inward)
        case .left: CGPoint(x: -1440 + inward, y: 450)
        case .right: CGPoint(x: -inward, y: 450)
        }
    }

    @Test("Intensity rises monotonically toward the zone and peaks at its inner boundary", arguments: DockEdge.allCases)
    func proximity(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge)
        let samples = stride(from: 260, through: 0, by: -20).map { geometry.sample(pointer: point(edge, inward: CGFloat($0))).intensity }
        #expect(samples.first == 0)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(geometry.sample(pointer: point(edge, inward: 8)).intensity == 1)
        #expect(geometry.sample(pointer: point(edge, inward: 8 + DockApproachGeometry.reach)).intensity == 0)
    }

    @Test("The band hugs the screen edge and the glow fades past either end of the zone", arguments: DockEdge.allCases)
    func band(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge)
        #expect(screen.contains(geometry.frame))
        #expect(geometry.depth == DockApproachGeometry.washDepth * (1 + DockApproachGeometry.surgeGrowth))
        #expect(geometry.zoneSpan.upperBound - geometry.zoneSpan.lowerBound == 360)
        let far: CGPoint = edge.isVertical ? CGPoint(x: point(edge, inward: 0).x, y: 270 - DockApproachGeometry.feather - 1)
            : CGPoint(x: -900 - DockApproachGeometry.feather - 1, y: point(edge, inward: 0).y)
        #expect(geometry.sample(pointer: far).intensity == 0)
        #expect(geometry.zoneSpan.contains(geometry.sample(pointer: far).focus))
    }

    @Test("The surge decays exponentially from the zone and vanishes at the reach boundary", arguments: DockEdge.allCases)
    func surge(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge)
        func surge(_ beyond: CGFloat) -> Double { geometry.sample(pointer: point(edge, inward: 8 + beyond)).surge }
        #expect(surge(0) == 1)
        #expect(abs(surge(DockApproachGeometry.surgeLength) - exp(-1)) < 0.01)
        #expect(surge(DockApproachGeometry.reach) == 0)
        // Each step closer adds more than the step before it.
        let steps = stride(from: 100, through: 0, by: -10).map { surge(CGFloat($0)) }
        let gains = zip(steps.dropFirst(), steps).map { $0 - $1 }
        #expect(zip(gains, gains.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("A mid-screen band holds the fully surged glow, so it never ends in a hard cut", arguments: DockEdge.allCases)
    func bandHoldsGlow(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge)
        let reach = DockApproachGeometry.washHalfWidth(zoneLength: 360) * (1 + DockApproachGeometry.surgeGrowth)
        #expect(geometry.zoneSpan.lowerBound >= reach)
        #expect(geometry.length - geometry.zoneSpan.upperBound >= reach)
    }

    @Test("A pointer on another display never lights this edge")
    func otherDisplay() {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(.bottom), edge: .bottom)
        #expect(geometry.sample(pointer: CGPoint(x: 200, y: 2)).intensity == 0)
    }

    @Test("Documents saved before the indicator existed decode with it off and the ghost on")
    func legacyDecoding() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DockBehaviorSettings())) as? [String: Any])
        object.removeValue(forKey: "approachIndicator")
        object.removeValue(forKey: "approachColor")
        object.removeValue(forKey: "approachGhost")
        let decoded = try JSONDecoder().decode(DockBehaviorSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == DockBehaviorSettings())
        #expect(decoded.approachGhost)
        var enabled = DockBehaviorSettings(); enabled.approachIndicator = true; enabled.approachColor = .accent; enabled.approachGhost = false
        #expect(try JSONDecoder().decode(DockBehaviorSettings.self, from: JSONEncoder().encode(enabled)) == enabled)
    }

    /// A dock's glass that sits farther inward than the glow reaches and runs past the zone's ends.
    private func dock(_ edge: DockEdge) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: -1100, y: 60, width: 760, height: 120)
        case .top: CGRect(x: -1100, y: 720, width: 760, height: 120)
        case .left: CGRect(x: -1380, y: 70, width: 120, height: 760)
        case .right: CGRect(x: -180, y: 70, width: 120, height: 760)
        }
    }

    @Test("With a ghost, the band grows to cover the resting dock and its rise", arguments: DockEdge.allCases)
    func bandCoversGhost(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge, ghost: dock(edge))
        let room = dock(edge).insetBy(dx: -DockApproachGeometry.ghostMargin, dy: -DockApproachGeometry.ghostMargin)
        #expect(geometry.frame.contains(room.intersection(screen)))
        #expect(screen.contains(geometry.frame))
        // The glow keeps its own reach: the sample does not depend on the ghost.
        let plain = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge)
        #expect(geometry.sample(pointer: point(edge, inward: 60)).intensity == plain.sample(pointer: point(edge, inward: 60)).intensity)
    }

    @Test("Local rects keep the screen's orientation on a display with a negative origin", arguments: DockEdge.allCases)
    func localRect(edge: DockEdge) {
        let geometry = DockApproachGeometry(screen: screen, zone: zone(edge), edge: edge, ghost: dock(edge))
        let local = geometry.localRect(dock(edge))
        #expect(local.size == dock(edge).size)
        #expect(CGRect(origin: .zero, size: geometry.frame.size).contains(local))
        #expect(local.minX == dock(edge).minX - geometry.frame.minX)
        #expect(local.maxY == geometry.frame.maxY - dock(edge).minY)
    }

    @Test("The ghost snapshot uses resting icon sizes and skips insertion gaps")
    func restingGhost() throws {
        let layout = DockGeometry.layout(count: 3, favoriteCount: 0, availableLength: 1440)
        let restingFrame = CGRect(x: -1100, y: 0, width: layout.viewportLength, height: layout.panelDepth)
        let ghost = DockApproachGhost.resting(slots: [.launcher, .gap("insertion"), .launcher], layout: layout,
                                              restingFrame: restingFrame, scrollOffset: 0, showsGlass: true, cornerRadius: 400)
        #expect(ghost.tiles.count == 2)
        #expect(ghost.tiles.allSatisfy { $0.frame.width == layout.iconSize && $0.frame.height == layout.iconSize && $0.icon == nil })
        let glass = try #require(ghost.glass)
        #expect(ghost.tiles.allSatisfy { glass.contains($0.frame) })
        // The radius is capped to a capsule, matching the drawn glass.
        #expect(ghost.cornerRadius == min(glass.width, glass.height) / 2)
        #expect(DockApproachGhost.resting(slots: [.launcher], layout: DockGeometry.layout(count: 1, favoriteCount: 0, availableLength: 1440),
                                          restingFrame: restingFrame, scrollOffset: 0, showsGlass: false, cornerRadius: 22).glass == nil)
    }
}
