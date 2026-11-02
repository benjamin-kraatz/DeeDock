import Foundation

/// What hosts an automatic prompt on screen. `AppHealthPromptPanelController` in the app; a fake in tests.
///
/// The host forwards pointer, keyboard, and button input to the session it shows. The coordinator calls
/// `close()` exactly once, after the session finished or was interrupted.
@MainActor
protocol AppHealthPromptPresenting: AnyObject {
    /// Removes the prompt and every monitor and observer it installed.
    func close()
}

/// What hosts the "Something's off right now…" picker. `AppHealthPickerPanelController` in the app.
@MainActor
protocol AppHealthPickerPresenting: AnyObject {
    /// The person picked an app from the list.
    var picked: ((AppHealthPickerEntry) -> Void)? { get set }
    /// The person closed the picker: Escape, or focus moved elsewhere. The coordinator then calls `close()`.
    var dismissed: (() -> Void)? { get set }
    /// Replaces the list with the label choices for the picked app.
    func showQuestion(_ session: AppHealthLabelSession)
    /// Brings an open picker forward again, for a second menu click.
    func present()
    /// Removes the picker and every monitor and observer it installed. Does not call `dismissed`.
    func close()
}

/// One watched app in the picker, from the latest tick.
struct AppHealthPickerEntry: Identifiable {
    let sample: AppHealthSample
    let display: AppHealthAppDisplay

    var id: String { sample.app }
}
