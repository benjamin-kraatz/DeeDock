import SwiftUI

/// One choice in a `SettingsOptionPicker`.
struct SettingsOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringResource
    let symbol: String

    var id: Value { value }
}

/// A segmented choice whose selection capsule slides between options.
///
/// Options share the available width so translated titles of different lengths stay aligned.
struct SettingsOptionPicker<Value: Hashable>: View {
    let title: LocalizedStringResource
    let options: [SettingsOption<Value>]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button { selection = option.value } label: {
                    Label { Text(option.title) } icon: { Image(systemName: option.symbol) }
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(selection == option.value ? AnyShapeStyle(.white)
                                                                   : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(.capsule)
                        .background {
                            if selection == option.value {
                                Capsule(style: .continuous)
                                    .fill(.tint)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(.quaternary.opacity(0.55)))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0.1), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// A choice presented under its own label, so long option titles keep full width.
struct SettingsPickerRow<Value: Hashable>: View {
    let title: LocalizedStringResource
    let options: [SettingsOption<Value>]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
            SettingsOptionPicker(title: title, options: options, selection: $selection)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
