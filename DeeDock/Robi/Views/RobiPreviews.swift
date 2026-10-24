#if DEBUG
import SwiftUI

/// Deterministic models for Robi's previews. Nothing here touches windows, models or the Keychain.
@MainActor
enum RobiPreviewData {
    static let lightTint = Color.white
    static let darkTint = Color(red: 0.21, green: 0.23, blue: 0.26)

    static func model(_ phase: RobiPhase, dark: Bool = false, placement: RobiPlacement = .above,
                      context: RobiContext? = nil, answer: String = "", notice: RobiNotice? = nil,
                      proposal: RobiProposal? = nil, model answerModel: RobiAnswerModel = .onDevice,
                      reduceMotion: Bool = false, toast: LocalizedStringResource? = nil) -> RobiModel {
        let model = RobiModel()
        model.phase = phase
        model.placement = placement
        model.isPresent = true
        model.tint = dark ? darkTint : lightTint
        model.tintIsDark = dark
        model.applicationName = dark ? "Ghostty" : "Petal Studio"
        model.context = context
        model.request = phase.showsCard ? String(localized: RobiIntent.translate.title) : ""
        model.answer = answer
        model.notice = notice
        model.proposal = proposal
        model.answerModel = answerModel
        model.canReplace = context?.kind == .selection
        model.reduceMotion = reduceMotion
        model.toast = toast
        return model
    }

    static let selection = RobiContext(kind: .selection, text: "We write like a smart friend who has five minutes.")
    static let region = RobiContext(kind: .region, text: "error: main actor-isolated property 'items' can not be referenced from a nonisolated context")
    static let longAnswer = """
    LibraryStore.items is isolated to the main actor, but sync() is nonisolated, so line 42 reads \
    main-actor state from an arbitrary thread.

    Two fixes:
    • If sync() only updates UI state, mark it @MainActor.
    • If it does slow work, read items on the main actor first, do the work, then hop back to \
    assign the result.
    """
}

/// Robi's panel at the size the controller would give it, over a stand-in for the window and desktop.
private struct RobiPreviewStage: View {
    let model: RobiModel
    var body: some View {
        RobiRootView(model: model, eyes: RobiEyes(), actions: RobiActions())
            .frame(width: model.panelSize(for: model.phase).width, height: model.panelSize(for: model.phase).height)
            .background(alignment: .top) {
                // The window's title bar, where the tab meets it; the desktop around it.
                VStack(spacing: 0) {
                    Color.clear.frame(height: model.placement == .above ? RobiMetrics.shadowMargin + RobiMetrics.tabHeight - 1 : 0)
                    model.tint
                }
            }
            .background(model.tintIsDark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(red: 0.86, green: 0.83, blue: 0.95))
    }
}

#Preview("Idle, light window") { RobiPreviewStage(model: RobiPreviewData.model(.idle)) }
#Preview("Awake, dark window") { RobiPreviewStage(model: RobiPreviewData.model(.awake, dark: true)) }
#Preview("Inside placement") { RobiPreviewStage(model: RobiPreviewData.model(.awake, dark: true, placement: .inside)) }
#Preview("Selecting") { RobiPreviewStage(model: RobiPreviewData.model(.selecting)) }
#Preview("Selecting, German, dark") {
    RobiPreviewStage(model: RobiPreviewData.model(.selecting, dark: true))
        .environment(\.locale, Locale(identifier: "de"))
}
#Preview("Prompting with selection") {
    RobiPreviewStage(model: RobiPreviewData.model(.prompting, context: RobiPreviewData.selection))
}
#Preview("Prompting inside, dark") {
    RobiPreviewStage(model: RobiPreviewData.model(.prompting, dark: true, placement: .inside, context: RobiPreviewData.region))
}
#Preview("Thinking, Claude (eyes wander)") {
    RobiPreviewStage(model: RobiPreviewData.model(.thinking, dark: true, context: RobiPreviewData.region, model: .claude))
}
#Preview("Thinking, on this Mac, light") {
    RobiPreviewStage(model: RobiPreviewData.model(.thinking, context: RobiPreviewData.selection))
}
#Preview("Answered") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, context: RobiPreviewData.selection,
        answer: "Wir schreiben wie eine kluge Freundin, die fünf Minuten Zeit hat.", toast: .robiToastCopied))
}
#Preview("Answered, long, scrolls") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, dark: true, context: RobiPreviewData.region,
        answer: RobiPreviewData.longAnswer, model: .claude))
}
#Preview("Proposed command, dark") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, dark: true, context: RobiPreviewData.region,
        answer: "Claude Code is waiting for input. I can open a new tab for the fix.",
        proposal: RobiProposal(path: "Shell > New Tab")))
}
#Preview("Claude key missing") {
    RobiPreviewStage(model: RobiPreviewData.model(.thinking, context: RobiPreviewData.selection,
        notice: .claudeKeyMissing, model: .claude))
}
#Preview("On-device unavailable") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, context: RobiPreviewData.selection,
        notice: .onDeviceUnavailable(.robiOnDeviceIntelligenceOff)))
}
#Preview("Screen Recording needed, dark") {
    RobiPreviewStage(model: RobiPreviewData.model(.thinking, dark: true, context: RobiPreviewData.region,
        notice: .screenRecordingNeeded))
}
#Preview("Failed") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, context: RobiPreviewData.selection,
        notice: .failed(String(localized: .robiErrorOffline)), model: .claude))
}
#Preview("Answered, German") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, context: RobiPreviewData.selection,
        answer: "Ein kurzer Stilleitfaden: freundlich, knapp und genau."))
        .environment(\.locale, Locale(identifier: "de"))
}
#Preview("Answered, Reduce Motion") {
    RobiPreviewStage(model: RobiPreviewData.model(.answered, dark: true, context: RobiPreviewData.selection,
        answer: "Short fades instead of springs; the eyes stay still.", reduceMotion: true))
}
#endif
