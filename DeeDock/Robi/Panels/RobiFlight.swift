import AppKit
import SwiftUI

/// Flies a picked region up into Robi's face: the dashed selection detaches from the sheet,
/// shrinks along an arc and fades as it reaches the face.
///
/// The overlay is a click-through panel ordered above Robi's own panel, so the piece can land on
/// the face in view, and it never takes a click, the keyboard or focus from the app. It lives for
/// one flight and takes itself off the screen when the flight is over; `hide()` ends it at once.
/// Its one task, the hide timer, is cancelled by every show and hide. The flight is short and the
/// window is not followed during it: a window moved in that half second lands the piece a few
/// points off, which is not worth a second geometry path.
@MainActor
final class RobiFlight {
    private let panel = RobiPanel()
    private let state = RobiFlightState()
    private var hideTask: Task<Void, Never>?

    init() {
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: RobiFlightView(state: state))
        host.sizingOptions = []
        panel.contentView = host
        // Decoration only: the face's reaction is the feedback, and VoiceOver hears the prompt open.
        panel.setAccessibilityElement(false)
    }

    /// Starts `path` now, replacing a flight still in the air. The overlay goes above
    /// `companion`, Robi's panel, so the piece stays visible until it has faded on the face.
    func show(_ path: RobiFlightPath, above companion: NSWindow?) {
        hideTask?.cancel()
        panel.setFrame(path.overlayFrame, display: true)
        state.flight = path
        panel.orderFrontRegardless()
        if let companion { panel.order(.above, relativeTo: companion.windowNumber) }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(path.duration + 0.1))
            guard !Task.isCancelled, let self, self.state.flight == path else { return }
            self.hide()
        }
    }

    /// Takes the overlay off the screen at once, mid-flight included.
    func hide() {
        hideTask?.cancel()
        hideTask = nil
        state.flight = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

/// What the flight overlay draws. Written only by `RobiFlight`.
@MainActor @Observable
final class RobiFlightState {
    /// The flight in the air, or nil between flights.
    var flight: RobiFlightPath?
}
