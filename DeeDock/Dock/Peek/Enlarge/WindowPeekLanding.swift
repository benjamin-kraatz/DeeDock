import SwiftUI

/// Flies a staged exhibit onto its real window after a click, then fades the stage away over it.
///
/// A landing outlives the Peek presentation that started it: selection closes Peek, and with it the
/// `WindowPeekEnlargeController`, while the picture is still in flight. So a landing owns the stage
/// panel from `start` on, and its animation completion and deadline task hold it strongly until the
/// panel is closed. Nothing may depend on the controller still existing, or the picture would stay on
/// screen forever (AppKit keeps an ordered-in window alive by itself).
@MainActor
final class WindowPeekLanding {
    /// Activation is asynchronous and can fail; the picture must never outstay this.
    static let deadline: Duration = .milliseconds(1_100)
    private let panel: WindowPeekStagePanelController
    private let exhibit: WindowPeekExhibit
    private var flown = false
    private var peekClosed = false
    private var finished = false
    private var deadlineTask: Task<Void, Never>?

    init(panel: WindowPeekStagePanelController, exhibit: WindowPeekExhibit) {
        self.panel = panel
        self.exhibit = exhibit
    }

    /// Starts the flight to `target`, a window frame in the stage's local space.
    func start(target: CGRect) {
        withAnimation(.spring(duration: 0.42, bounce: 0.06)) {
            exhibit.landing = target
            panel.stage.dimmed = false
        } completion: { [self] in
            flown = true
            finishIfReady()
        }
        deadlineTask = Task { @MainActor [self] in
            try? await Task.sleep(for: Self.deadline)
            guard !Task.isCancelled else { return }
            flown = true
            peekClosed = true
            finishIfReady()
        }
    }

    /// Selection finished and Peek closed, so the real window should now be frontmost.
    func peekDidClose() {
        peekClosed = true
        finishIfReady()
    }

    /// Fades the whole stage window, revealing the window underneath, then orders it out.
    private func finishIfReady() {
        guard flown, peekClosed, !finished else { return }
        finished = true
        deadlineTask?.cancel()
        deadlineTask = nil
        panel.close(animated: true, duration: 0.22)
    }
}
