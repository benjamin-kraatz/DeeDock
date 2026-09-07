import SwiftUI

/// One choice in a `SettingsOptionPicker`.
struct SettingsOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringResource
    let symbol: String

    var id: Value { value }
}

/// A native segmented picker with system keyboard navigation and selection rendering.
struct SettingsOptionPicker<Value: Hashable>: View {
    let title: LocalizedStringResource
    let options: [SettingsOption<Value>]
    @Binding var selection: Value

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        } label: {
            Text(title)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}

/// A labeled pop-up menu for placement and other discrete preferences.
struct SettingsPickerRow<Value: Hashable>: View {
    let title: LocalizedStringResource
    let options: [SettingsOption<Value>]
    @Binding var selection: Value

    var body: some View {
        SettingsMenuRow(title: title, selection: $selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.value)
            }
        }
    }
}
