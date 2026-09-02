import SwiftUI

/// Locale-aware numeric editing for one setting, drawn as a compact value pill.
///
/// An incomplete or out-of-range draft stays inside this field: only a parsed value within
/// `range` is published, so partially typed text never reaches persistence or the dock.
struct SettingsValueField: View {
    let title: LocalizedStringResource
    let unit: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var text = ""
    @FocusState private var editing: Bool

    private var parsedValue: Double? {
        guard let number = try? Double(text, format: .number, lenient: false), number.isFinite,
              range.contains(number) else { return nil }
        return number
    }
    private var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
    private var isInvalid: Bool { editing && parsedValue == nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            TextField(text: $text) { Text(title) }
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
                .focused($editing)
                .accessibilityLabel(Text(title))
                .help(Text(.settingsAllowedRange(lower: range.lowerBound.formatted(),
                                                 upper: range.upperBound.formatted())))
                .onSubmit { text = formattedValue }
            Text(unit)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(background)
        .overlay(alignment: .trailing) { invalidBadge }
        .animation(.snappy(duration: 0.18), value: editing)
        .animation(.snappy(duration: 0.18), value: isInvalid)
        .onAppear { text = formattedValue }
        .onChange(of: text) { _, _ in
            if editing, let parsedValue { value = parsedValue }
        }
        .onChange(of: value) { _, _ in
            let draft = parsedValue.map { ($0 / step).rounded() * step }
            if !editing || draft == nil || abs((draft ?? value) - value) > 0.000001 {
                text = formattedValue
            }
        }
        // Invalid drafts never leave this field; leaving it restores the last accepted value.
        .onChange(of: editing) { _, focused in if !focused { text = formattedValue } }
    }

    @ViewBuilder private var background: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            shape.fill(editing ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6)))
            shape.strokeBorder(isInvalid ? AnyShapeStyle(Color.red)
                                : editing ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                               lineWidth: 1)
        }
    }

    /// Inline, non-blocking signal; the accessible explanation stays on the field's help text.
    @ViewBuilder private var invalidBadge: some View {
        if isInvalid {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .offset(x: 16)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(.settingsInvalidNumber))
        }
    }
}
