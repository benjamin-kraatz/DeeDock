import CoreGraphics
import Foundation
import Testing
@testable import DeeDock

/// Placement, lighting and proximity math in AppKit global coordinates, including displays left
/// of and below the primary one.
struct VaporGeometryTests {
    private let primary = VaporDisplay(id: "display.main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950), isPrimary: true)
    /// To the left of and lower than the primary display: negative origin on both axes.
    private let left = VaporDisplay(id: "display.left", frame: CGRect(x: -2560, y: -400, width: 2560, height: 1440),
                                    visibleFrame: CGRect(x: -2560, y: -400, width: 2560, height: 1415), isPrimary: false)

    private func approx(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

    @Test func panelOpensTowardTheScreenCentre() {
        let size = CGSize(width: 340, height: 400)
        let rightOrb = CGPoint(x: 1400, y: 300)
        let leftward = VaporGeometry.panelFrame(orbCenter: rightOrb, size: size, visibleFrame: primary.visibleFrame)
        #expect(approx(leftward.maxX, rightOrb.x - VaporGeometry.orbDiameter / 2 - VaporGeometry.panelGap))
        let leftOrb = CGPoint(x: 150, y: 300)
        let rightward = VaporGeometry.panelFrame(orbCenter: leftOrb, size: size, visibleFrame: primary.visibleFrame)
        #expect(approx(rightward.minX, leftOrb.x + VaporGeometry.orbDiameter / 2 + VaporGeometry.panelGap))
        // Its top sits about 62 % of its height above the orb's centre.
        #expect(approx(rightward.maxY, leftOrb.y + size.height * 0.62))
    }

    @Test func panelIsClampedInsideTheVisibleFrameOnNegativeOrigins() {
        let size = CGSize(width: 340, height: 600)
        let nearBottom = CGPoint(x: -2500, y: -380)
        let frame = VaporGeometry.panelFrame(orbCenter: nearBottom, size: size, visibleFrame: left.visibleFrame)
        let inner = left.visibleFrame.insetBy(dx: VaporGeometry.panelMargin, dy: VaporGeometry.panelMargin)
        #expect(inner.contains(frame))
        #expect(approx(frame.minY, inner.minY))
        let nearTop = CGPoint(x: -100, y: 1000)
        let top = VaporGeometry.panelFrame(orbCenter: nearTop, size: size, visibleFrame: left.visibleFrame)
        #expect(inner.contains(top))
        #expect(top.maxX <= nearTop.x)
        // A panel taller than the display shrinks to fit.
        let huge = VaporGeometry.panelFrame(orbCenter: CGPoint(x: 700, y: 400), size: CGSize(width: 340, height: 3000),
                                            visibleFrame: primary.visibleFrame)
        #expect(approx(huge.height, primary.visibleFrame.height - VaporGeometry.panelMargin * 2))
    }

    @Test func placementRoundTripsAndClamps() {
        let center = CGPoint(x: -1200, y: 300)
        let placement = VaporGeometry.placement(center: center, in: left.visibleFrame)
        let back = VaporGeometry.center(for: placement, in: left.visibleFrame)
        #expect(approx(back.x, center.x) && approx(back.y, center.y))
        // Off-screen centres are pulled in so the whole orb is visible.
        let clamped = VaporGeometry.clampedCenter(CGPoint(x: 5000, y: -5000), in: primary.visibleFrame)
        let inset = VaporGeometry.orbDiameter / 2 + VaporGeometry.screenMargin
        #expect(approx(clamped.x, primary.visibleFrame.maxX - inset))
        #expect(approx(clamped.y, primary.visibleFrame.minY + inset))
    }

    @Test func positionIsRestoredPerDisplayAndFallsBackToTheMainDisplay() {
        var state = VaporPersistedState()
        state.placements = [left.id: VaporOrbPlacement(x: 0.25, y: 0.5), primary.id: VaporOrbPlacement(x: 0.9, y: 0.2)]
        state.displayID = left.id
        let both = VaporGeometry.resolve(state, displays: [primary, left])
        #expect(both?.display.id == left.id)
        #expect(both.map { approx($0.center.x, -2560 + 2560 * 0.25) && approx($0.center.y, -400 + 1415 * 0.5) } == true)
        // The left display is unplugged: the orb goes to the main display at its own placement.
        let unplugged = VaporGeometry.resolve(state, displays: [primary])
        #expect(unplugged?.display.id == primary.id)
        #expect(unplugged.map { approx($0.center.x, 1512 * 0.9) } == true)
        // Replugged: it returns, because the fallback isn't saved.
        #expect(VaporGeometry.resolve(state, displays: [left, primary])?.display.id == left.id)
        // No placement yet on the main display: the default spot.
        state.placements[primary.id] = nil
        let fresh = VaporGeometry.resolve(state, displays: [primary])
        #expect(fresh.map { $0.center == VaporGeometry.defaultCenter(in: primary.visibleFrame) } == true)
        #expect(VaporGeometry.resolve(state, displays: []) == nil)
    }

    @Test func displayUnderAPointOrTheNearest() {
        #expect(VaporGeometry.display(at: CGPoint(x: -10, y: 0), in: [primary, left])?.id == left.id)
        #expect(VaporGeometry.display(at: CGPoint(x: 10, y: 10), in: [primary, left])?.id == primary.id)
        // In the gap below the primary display and right of the left one.
        #expect(VaporGeometry.display(at: CGPoint(x: 800, y: -300), in: [primary, left])?.id == primary.id)
    }

    @Test func lampLightingFollowsTheOrb() {
        // Straight below the lamp: highlight up, no sideways shadow.
        let below = VaporGeometry.lighting(orbCenter: CGPoint(x: primary.frame.midX, y: 500), displayFrame: primary.frame)
        #expect(abs(below.angle) < 1e-9)
        #expect(abs(below.shadowOffset.width) < 1e-9)
        #expect(below.shadowStretch == 1)
        // Right of centre: the lamp is up and to the left, the shadow slides right.
        let right = VaporGeometry.lighting(orbCenter: CGPoint(x: 1400, y: 500), displayFrame: primary.frame)
        #expect(right.angle < 0)
        #expect(right.shadowOffset.width > 0)
        #expect(right.shadowStretch > 1)
        let leftSide = VaporGeometry.lighting(orbCenter: CGPoint(x: 100, y: 500), displayFrame: primary.frame)
        #expect(leftSide.angle > 0)
        #expect(leftSide.shadowOffset.width < 0)
        // Further from the lamp is fainter, within bounds.
        let near = VaporGeometry.lighting(orbCenter: CGPoint(x: primary.frame.midX, y: 900), displayFrame: primary.frame)
        let far = VaporGeometry.lighting(orbCenter: CGPoint(x: 60, y: 60), displayFrame: primary.frame)
        #expect(near.intensity > far.intensity)
        #expect((0.5...1.15).contains(near.intensity) && (0.5...1.15).contains(far.intensity))
        // The same relative spot on a negative-origin display lights the same way.
        let scaledCenter = CGPoint(x: left.frame.minX + left.frame.width * (1400 / 1512),
                                   y: left.frame.minY + left.frame.height * (500 / 982))
        let mirrored = VaporGeometry.lighting(orbCenter: scaledCenter, displayFrame: left.frame)
        #expect(mirrored.angle < 0 && mirrored.shadowOffset.width > 0)
    }

    @Test func badgeSitsOnTheCornerFacingAway() {
        #expect(VaporGeometry.badgeCorner(orbCenter: CGPoint(x: 1400, y: 300), visibleFrame: primary.visibleFrame) == .topTrailing)
        #expect(VaporGeometry.badgeCorner(orbCenter: CGPoint(x: -2400, y: 300), visibleFrame: left.visibleFrame) == .topLeading)
    }

    @Test func satellitesArcTowardTheCentreAndStayOnScreen() throws {
        let orb = CGPoint(x: 1400, y: 300)
        let layout = VaporGeometry.satelliteLayout(orbCenter: orb, count: 7, capsuleSize: CGSize(width: 260, height: 34),
                                                   visibleFrame: primary.visibleFrame)
        #expect(layout.bubbleCenters.count == VaporGeometry.maxBubbles)
        let window = layout.windowFrame
        let rho = VaporGeometry.orbDiameter / 2 + 32
        for local in layout.bubbleCenters {
            let global = CGPoint(x: window.minX + local.x, y: window.maxY - local.y)
            #expect(approx(hypot(global.x - orb.x, global.y - orb.y), rho, 0.5))
            // Bubbles face the screen centre, so they sit left of an orb on the right.
            #expect(global.x < orb.x)
        }
        // Neighbours are 0.4 rad apart on the arc.
        try #require(layout.bubbleCenters.count >= 2)
        let a = layout.bubbleCenters[0], b = layout.bubbleCenters[1]
        let chord = 2 * rho * sin(CGFloat(VaporGeometry.bubbleStep) / 2)
        #expect(approx(hypot(a.x - b.x, a.y - b.y), chord, 0.5))
        // The orb's own position in window coordinates is exact.
        #expect(approx(layout.orbCenter.x, orb.x - window.minX) && approx(layout.orbCenter.y, window.maxY - orb.y))
        let capsule = CGPoint(x: window.minX + layout.capsuleCenter.x, y: window.maxY - layout.capsuleCenter.y)
        #expect(primary.visibleFrame.contains(capsule))
        #expect(VaporGeometry.satelliteLayout(orbCenter: orb, count: 0, capsuleSize: .zero,
                                              visibleFrame: primary.visibleFrame).bubbleCenters.isEmpty)
    }

    @Test func calloutGoesAboveTheOrbOrBelowNearTheTop() {
        let size = CGSize(width: 220, height: 36)
        let above = VaporGeometry.statusFrame(orbCenter: CGPoint(x: 700, y: 300), size: size, visibleFrame: primary.visibleFrame)
        #expect(above.minY > 300 + VaporGeometry.orbDiameter / 2)
        let below = VaporGeometry.statusFrame(orbCenter: CGPoint(x: 700, y: 900), size: size, visibleFrame: primary.visibleFrame)
        #expect(below.maxY < 900 - VaporGeometry.orbDiameter / 2)
        let edge = VaporGeometry.statusFrame(orbCenter: CGPoint(x: -2550, y: 0), size: size, visibleFrame: left.visibleFrame)
        #expect(edge.minX >= left.visibleFrame.minX)
    }

    @Test func dropProximityRisesTowardTheOrb() {
        let orb = CGPoint(x: 500, y: 500)
        let radius = VaporGeometry.orbDiameter / 2
        #expect(VaporGeometry.dropProximity(point: CGPoint(x: 500 + radius + 300, y: 500), orbCenter: orb) == .none)
        let edge = VaporGeometry.dropProximity(point: CGPoint(x: 500 + radius, y: 500), orbCenter: orb)
        #expect(edge.value == 1 && edge.isOverOrb)
        let mid = VaporGeometry.dropProximity(point: CGPoint(x: 500 + radius + 95, y: 500), orbCenter: orb)
        #expect(abs(mid.value - 0.25) < 1e-9)
        #expect(!mid.isOverOrb)
        #expect(VaporGeometry.dropProximity(point: CGPoint(x: 500, y: 500 + radius + 20), orbCenter: orb).isOverOrb)
        // Lean points at the pointer, in SwiftUI's y-down space.
        let aboveRight = VaporGeometry.dropProximity(point: CGPoint(x: 560, y: 560), orbCenter: orb)
        #expect(aboveRight.lean.width > 0 && aboveRight.lean.height < 0)
        #expect(hypot(edge.lean.width, edge.lean.height) <= 7.0001)
    }
}
