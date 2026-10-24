import AppKit
import SwiftUI

/// Shows the person where something from Robi's answer is: a soft dim over the window with a
/// glowing ring around one landmark.
///
/// The overlay is a click-through panel laid over the target window, below Robi's own panel, so
/// it never takes a click, the keyboard or focus from the app. It follows the window as it moves
/// and fades out on its own after `holdDuration`; a new reference moves the ring there instead.
/// The controller hides it when the interaction ends. Its one task, the fade-out timer, is
/// cancelled by every show and hide.
@MainActor
final class RobiSpotlight {
    private let panel = RobiPanel()
    private let state = RobiSpotlightState()
    private var hideTask: Task<Void, Never>?

    /// How long the spotlight stays before it fades by itself.
    static let holdDuration: Duration = .seconds(5)
    /// Long enough for the fade-out to finish before the panel leaves the screen.
    private static let fadeDuration: Duration = .milliseconds(380)

    init() {
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: RobiSpotlightView(state: state))
        host.sizingOptions = []
        panel.contentView = host
        // VoiceOver hears an announcement instead; the overlay itself is decoration.
        panel.setAccessibilityElement(false)
    }

    /// Rings `landmark`, a rect in window-local top-left points, on the window given in AppKit
    /// points, and starts the fade-out timer again.
    func show(_ landmark: CGRect, over window: CGRect, below companion: NSWindow?, reduceMotion: Bool, reduceTransparency: Bool) {
        hideTask?.cancel()
        state.reduceMotion = reduceMotion
        state.reduceTransparency = reduceTransparency
        let wasShown = panel.isVisible && state.isShown
        panel.setFrame(window, display: true)
        if !wasShown {
            // Placed without animation, so the ring lands on the spot instead of flying in from
            // wherever the last one was.
            var placement = Transaction()
            placement.disablesAnimations = true
            withTransaction(placement) { state.target = landmark }
            panel.orderFrontRegardless()
            if let companion { companion.order(.above, relativeTo: panel.windowNumber) }
        } else {
            state.target = landmark
        }
        state.isShown = true
        state.pulse += 1
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Keeps the overlay on the window while it moves or resizes. Landmarks are relative to the
    /// window's top-left corner, so the ring moves with it.
    func move(over window: CGRect) {
        guard panel.isVisible, panel.frame != window else { return }
        panel.setFrame(window, display: true)
    }

    /// Fades the spotlight out, then takes the panel off the screen.
    func hide() {
        hideTask?.cancel()
        guard panel.isVisible else { return }
        state.isShown = false
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fadeDuration)
            guard !Task.isCancelled, let self, !self.state.isShown else { return }
            self.panel.orderOut(nil)
        }
    }
}

/// What the spotlight draws. Written only by `RobiSpotlight`.
@MainActor @Observable
final class RobiSpotlightState {
    /// The landmark, in the overlay's own top-left points, which are the window's.
    var target: CGRect = .zero
    var isShown = false
    /// Counts shows, so each one plays the ring's pulse again.
    var pulse = 0
    var reduceMotion = false
    var reduceTransparency = false
}
