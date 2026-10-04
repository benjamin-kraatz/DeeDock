import Foundation

/// How a person reached an action.
nonisolated enum AnalyticsTrigger: String, AnalyticsToken {
    case click, keyboard, voiceOver = "voice_over", menu, drag, springLoad = "spring_load", hover
    /// A global shortcut pressed outside the dock.
    case hotkey
    /// The action followed from another DOKK feature rather than a direct gesture.
    case automatic
    /// The action was taken inside the Launcher.
    case launcher
}

extension Analytics {
    /// Runs `body` with `trigger` as the ambient trigger.
    ///
    /// Most actions funnel through one function that cannot tell a click from a context-menu
    /// item or a VoiceOver action. The entry point that does know wraps its call here, and the
    /// funnel reads ``trigger(keyboard:)``. The value applies only to synchronous work inside
    /// `body`; a funnel that reports from a completion handler must read the trigger first.
    static func performing<Result>(_ trigger: AnalyticsTrigger, _ body: () throws -> Result) rethrows -> Result {
        let previous = shared.ambientTrigger
        shared.ambientTrigger = trigger
        defer { shared.ambientTrigger = previous }
        return try body()
    }

    /// The ambient trigger, or keyboard or click according to `keyboard` when none is set.
    static func trigger(keyboard: Bool = false) -> AnalyticsTrigger {
        shared.ambientTrigger ?? (keyboard ? .keyboard : .click)
    }
}
