import SwiftUI

/// A rating scale drawn as a row of keys that light up like a level meter.
///
/// Hovering a key lights every key up to it, brighter toward the high end, so the scale reads
/// as "how much" before anything is clicked. With the submit button turned off a click answers
/// after a short beat, as in ``LauncherSurveyChoiceField``.
struct LauncherSurveyRatingField: View {
    let rating: AnalyticsSurvey.Rating
    let isOptional: Bool
    let buttonText: String?
    let submit: (AnalyticsSurveyAnswer?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?
    @State private var selected: Int?
    @State private var committed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(rating.values), id: \.self) { value in key(value) }
            }
            .disabled(committed)
            .onHover { if !$0 { hovered = nil } }
            if rating.lowerLabel != nil || rating.upperLabel != nil {
                HStack {
                    if let lower = rating.lowerLabel { Text(verbatim: lower) }
                    Spacer(minLength: 12)
                    if let upper = rating.upperLabel { Text(verbatim: upper) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            if isOptional || !rating.submitsOnSelection {
                // A scale that answers on click needs only Skip.
                LauncherSurveySubmitRow(buttonText: buttonText, canSubmit: selected != nil && !committed,
                                        showsSubmit: !rating.submitsOnSelection,
                                        skip: isOptional ? { submit(nil) } : nil) {
                    if let selected { submit(.rating(selected)) }
                }
            }
        }
        .task(id: committed) {
            guard committed, let selected else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 420))
            guard !Task.isCancelled else { return }
            submit(.rating(selected))
        }
    }

    private func key(_ value: Int) -> some View {
        let lit = hovered ?? selected
        return Button {
            withAnimation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback) {
                selected = value
                if rating.submitsOnSelection { committed = true }
            }
        } label: {
            Text(verbatim: rating.usesEmoji ? emoji(value) : String(value))
                .font(rating.usesEmoji ? .title3 : .system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(LauncherSurveyKeyStyle(level: lit.map { value <= $0 ? level(of: value) : nil } ?? nil,
                                            isSelected: selected == value, isHovered: hovered == value))
        .onHover { inside in
            if inside { hovered = value } else if hovered == value { hovered = nil }
        }
        .accessibilityLabel(Text(.launcherSurveyRatingValue(value, rating.values.upperBound)))
        .accessibilityAddTraits(selected == value ? .isSelected : [])
    }

    /// 0.35 at the low end to 1 at the high end.
    private func level(of value: Int) -> Double {
        let span = Double(rating.values.upperBound - rating.values.lowerBound)
        return 0.35 + 0.65 * Double(value - rating.values.lowerBound) / max(1, span)
    }

    /// PostHog's faces for 3- and 5-point emoji scales.
    private func emoji(_ value: Int) -> String {
        let faces = rating.scale == 3 ? ["🙁", "😐", "🙂"] : ["😞", "🙁", "😐", "🙂", "😀"]
        return faces.indices.contains(value - 1) ? faces[value - 1] : String(value)
    }
}

/// One key of the rating scale. `level` is nil when unlit, otherwise its brightness.
private struct LauncherSurveyKeyStyle: ButtonStyle {
    let level: Double?
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        LauncherSurveyKey(configuration: configuration, level: level, isSelected: isSelected, isHovered: isHovered)
    }
}

private struct LauncherSurveyKey: View {
    let configuration: ButtonStyleConfiguration
    let level: Double?
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .foregroundStyle(isSelected || (level ?? 0) > 0.6 ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                shape.fill(.fill.tertiary)
                shape.fill(.tint).opacity(isSelected ? 1 : level ?? 0)
            }
            .overlay { shape.strokeBorder(.white.opacity(isSelected ? 0.3 : 0.06)) }
            .shadow(color: .accentColor.opacity(isSelected ? 0.4 : 0), radius: 8, y: 3)
            .contentShape(shape)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.93 : isSelected ? 1.06 : isHovered ? 1.05 : 1)
            .offset(y: reduceMotion || !isHovered ? 0 : -1)
            .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback, value: level)
            .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback, value: isHovered)
            .animation(LauncherSurveyMotion(reduceMotion: reduceMotion).feedback, value: configuration.isPressed)
    }
}
