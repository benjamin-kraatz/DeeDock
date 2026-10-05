import SwiftUI

/// A free-text answer that grows from three to six lines.
///
/// The field takes keyboard focus once the question has slid in, since the person just chose
/// to say more. It reports focus through `focusChanged` so the launcher stops treating arrow
/// keys and Escape as navigation while someone is typing. The author's length limits are
/// enforced as typed, and a counter appears as the limit gets close.
struct LauncherSurveyTextField: View {
    let limits: AnalyticsSurvey.TextLimits
    let isOptional: Bool
    let buttonText: String?
    let focusChanged: (Bool) -> Void
    let submit: (AnalyticsSurveyAnswer?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var text = ""

    private var canSubmit: Bool { limits.accepts(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            TextField(text: $text, prompt: Text(.launcherSurveyAnswerPlaceholder), axis: .vertical) {
                Text(.launcherSurveyAnswerLabel)
            }
            .textFieldStyle(.plain)
            .lineLimit(3...6)
            .focused($focused)
            .onSubmit { if canSubmit { send() } }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(shape.fill(.background.opacity(0.55)))
            .overlay {
                shape.strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: focused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: focused)
            HStack(spacing: 12) {
                if let maximum = limits.maximum, text.count >= maximum * 3 / 4 {
                    Text(.launcherSurveyCharacterCount(text.count, maximum))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(text.count >= maximum ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .contentTransition(.numericText(value: Double(text.count)))
                        .transition(.opacity)
                }
                LauncherSurveySubmitRow(buttonText: buttonText, canSubmit: canSubmit,
                                        skip: isOptional ? { submit(nil) } : nil, submit: send)
            }
            .animation(.easeOut(duration: 0.2), value: text.count)
        }
        .onChange(of: text) { _, value in
            if let maximum = limits.maximum, value.count > maximum { text = String(value.prefix(maximum)) }
        }
        .onChange(of: focused) { _, value in focusChanged(value) }
        .task {
            // Wait for the step transition, so the caret appears in the field's final place.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 380))
            if !Task.isCancelled { focused = true }
        }
        .onDisappear { focusChanged(false) }
    }

    private func send() {
        focused = false
        submit(.text(text))
    }
}
