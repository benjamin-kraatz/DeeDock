import SwiftUI

/// Makes Robi's face the tab's handle: a press squeezes the face, a click asks or dismisses, and
/// a drag moves the tab along the window's top edge.
///
/// One `DragGesture(minimumDistance: 0)` drives all three, so a press is never claimed by a click
/// and a drag at once. The gesture only reports that something happened. Its translation is
/// ignored: the panel, and with it this view's coordinate space, moves under the pointer while the
/// tab is dragged, so the controller reads the pointer in screen points instead.
struct RobiFaceHandle: ViewModifier {
    let report: (RobiFaceGesture) -> Void
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .environment(\.robiFacePressed, isPressed)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isPressed) { _, pressed, _ in pressed = true }
                    .onChanged { _ in report(.changed) }
                    .onEnded { _ in report(.ended) }
            )
            .onChange(of: isPressed) { _, pressed in
                // A gesture SwiftUI cancels resets its state without calling `onEnded`. Deferred to
                // the next turn of the main actor so that after a real release `onEnded` has
                // already run, and the controller finds no press left to cancel.
                guard !pressed else { return }
                Task { @MainActor in report(.cancelled) }
            }
    }
}
