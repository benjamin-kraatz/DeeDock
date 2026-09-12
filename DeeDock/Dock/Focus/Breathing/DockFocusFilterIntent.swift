import AppIntents

/// Opt-in appearance filter delivered by macOS to the running app.
/// The default must stay false: macOS delivers defaults when the filter stops applying.
struct DockFocusFilterIntent: SetFocusFilterIntent {
    // App Intents metadata extraction requires literal resource initializers here.
    // These use the same catalog keys as the generated symbols in DDock's views.
    static var title: LocalizedStringResource = LocalizedStringResource(
        "focusBreathingTitle", defaultValue: "Focus breathing")
    static var description: IntentDescription = IntentDescription(LocalizedStringResource(
        "focusBreathingFilterDescription",
        defaultValue: "Gently animate DDock’s background during this Focus. Enable Focus breathing in DDock Settings first."))

    @Parameter(title: LocalizedStringResource("focusBreathingEnable", defaultValue: "Breathe dock background"),
               default: false)
    var breathe: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: .focusBreathingTitle,
                              subtitle: breathe ? .focusBreathingFilterOn : .focusBreathingFilterOff)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusBreathingStore.shared.receiveSystemFocus(breathe)
        return .result()
    }
}
