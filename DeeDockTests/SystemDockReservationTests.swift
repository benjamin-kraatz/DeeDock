import Testing
import CoreGraphics
@testable import DeeDock

/// The tour's macOS Dock guide reports what it measures, so the measurement has to be exact
/// about which insets belong to the Dock and which belong to the menu bar.
@Suite("System Dock reservation")
struct SystemDockReservationTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// Every screen loses its top band to the menu bar, whatever the Dock is doing.
    private let menuBar: CGFloat = 38

    private func visible(bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0,
                         in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + left, y: frame.minY + bottom,
               width: frame.width - left - right, height: frame.height - bottom - menuBar)
    }

    @Test("A Dock at the bottom reserves the bottom edge")
    func bottomDock() {
        let edge = SystemDockReservation.reservedEdge(frame: screen, visibleFrame: visible(bottom: 74, in: screen))
        #expect(edge == .bottom)
    }

    @Test("A Dock on the left reserves the left edge")
    func leftDock() {
        let edge = SystemDockReservation.reservedEdge(frame: screen, visibleFrame: visible(left: 64, in: screen))
        #expect(edge == .left)
    }

    @Test("A Dock on the right reserves the right edge")
    func rightDock() {
        let edge = SystemDockReservation.reservedEdge(frame: screen, visibleFrame: visible(right: 64, in: screen))
        #expect(edge == .right)
    }

    @Test("The menu bar alone is not a reservation")
    func menuBarOnly() {
        #expect(SystemDockReservation.reservedEdge(frame: screen, visibleFrame: visible(in: screen)) == nil)
    }

    @Test("A hidden Dock releases the space it held")
    func hiddenDock() {
        let reserving = visible(bottom: 74, in: screen)
        let released = visible(in: screen)
        #expect(SystemDockReservation.reservedEdge(frame: screen, visibleFrame: reserving) == .bottom)
        #expect(SystemDockReservation.reservedEdge(frame: screen, visibleFrame: released) == nil)
    }

    @Test("Sub-point insets from display scaling are not a reservation")
    func roundingTolerance() {
        let edge = SystemDockReservation.reservedEdge(frame: screen, visibleFrame: visible(bottom: 0.5, left: 0.75, in: screen))
        #expect(edge == nil)
    }

    @Test("A screen left of the primary display keeps its negative origin")
    func negativeOrigin() {
        let secondary = CGRect(x: -1680, y: -220, width: 1680, height: 1050)
        let edge = SystemDockReservation.reservedEdge(frame: secondary, visibleFrame: visible(bottom: 70, in: secondary))
        #expect(edge == .bottom)
    }

    @Test("An empty frame reports nothing rather than guessing")
    func emptyFrame() {
        #expect(SystemDockReservation.reservedEdge(frame: .zero, visibleFrame: .zero) == nil)
    }

    @Test("The Dock is reported when it is in the way on any connected display")
    func anyDisplayReserving() {
        let clear = (frame: screen, visibleFrame: visible(in: screen))
        let secondary = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let reserving = (frame: secondary, visibleFrame: visible(right: 66, in: secondary))
        #expect(SystemDockReservation.reservedEdge(in: [clear, reserving]) == .right)
        #expect(SystemDockReservation.reservedEdge(in: [clear]) == nil)
        #expect(SystemDockReservation.reservedEdge(in: []) == nil)
    }
}
