import SwiftUI

/// The open rail's last line: how to use a row, or a short note when an action could not reach
/// the picker. The note crossfades over the hints.
struct FlixPickFooter: View {
    let state: FlixPickState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            FlixHairline()
            ZStack(alignment: .leading) {
                if let message = state.message {
                    Text(verbatim: message)
                        .foregroundStyle(FlixPickStyle.warning(dark: colorScheme == .dark))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .transition(.opacity)
                } else {
                    FlixPickHints(kind: state.kind)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 10.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .animation(FlixMotion.fade, value: state.message)
        }
        .frame(height: FlixPickPlacement.footerHeight)
        .flixPickReveal(state.isOpen)
        .accessibilityHidden(!state.isOpen)
    }
}

/// "Click selects", "⌥-click opens", "or drag it in", spaced as in the mockup. A translation too
/// long for the rail first moves the hints closer, then drops the last one, then shrinks a little.
private struct FlixPickHints: View {
    let kind: FlixPickPickerKind

    var body: some View {
        let click: LocalizedStringResource = kind == .save ? .flixPickHintClickGoesThere : .flixPickHintClickSelects
        let option: LocalizedStringResource = kind == .save ? .flixPickHintOptionSaves : .flixPickHintOptionOpens
        ViewThatFits(in: .horizontal) {
            line([click, option, .flixPickHintDrag], spacing: 10)
            line([click, option, .flixPickHintDrag], spacing: 7)
            line([click, option], spacing: 10)
            line([click, option], spacing: 7).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ hints: [LocalizedStringResource], spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(hints, id: \.key) { FlixPickHint(text: $0) }
        }
    }
}

/// One hint, such as "Click **selects**": faint, with the words the translation emphasises in
/// Markdown one level stronger.
private struct FlixPickHint: View {
    let text: LocalizedStringResource

    @Environment(\.locale) private var locale

    var body: some View {
        Text(styled)
            .foregroundStyle(FlixStyle.faint)
            .lineLimit(1)
    }

    private var styled: AttributedString {
        // Looked up in the view's locale, so a preview in another language shows that language.
        var resource = text
        resource.locale = locale
        var string = AttributedString(localized: resource)
        for run in string.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            string[run.range].inlinePresentationIntent = nil
            string[run.range].swiftUI.font = .system(size: 10.5, weight: .medium)
            string[run.range].swiftUI.foregroundColor = FlixPickStyle.emphasis
        }
        return string
    }
}
