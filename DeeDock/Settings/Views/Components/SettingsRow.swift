import SwiftUI

/// Shared measurements so every settings surface lands on the same grid.
///
/// One place to tune the rhythm of the window: rows, cards, and separators all read from here
/// instead of repeating literals, which is what let the panes drift apart as they grew.
enum SettingsMetrics {
    static let cardRadius: CGFloat = 10
    static let cardSpacing: CGFloat = 20
    static let rowInset: CGFloat = 14
    static let rowVerticalInset: CGFloat = 9
    static let rowMinimumHeight: CGFloat = 32
    static let controlSpacing: CGFloat = 8
}

/// One line of a settings card: label on the leading edge, its control on the trailing edge.
///
/// This is the shape macOS uses everywhere in System Settings, and the reason rows in a card
/// line up with each other no matter which control they carry.
struct SettingsRow<Control: View>: View {
    let title: LocalizedStringResource
    /// Secondary copy for a row whose title cannot carry the whole explanation.
    var subtitle: LocalizedStringResource?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SettingsMetrics.controlSpacing)
            control
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
    }
}

/// A row whose control needs the full width, stacked under its label.
struct SettingsStackedRow<Content: View>: View {
    /// Omit for content that is its own heading, such as a preview or a gallery.
    var title: LocalizedStringResource?
    var subtitle: LocalizedStringResource?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A boolean setting drawn the way macOS draws one: a switch pinned to the trailing edge.
struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A short enumerated setting as a trailing pop-up menu, for choices that do not deserve a gallery.
struct SettingsMenuRow<Value: Hashable, Content: View>: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    @Binding var selection: Value
    @ViewBuilder var content: Content

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Picker(selection: $selection) { content } label: { Text(title) }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
    }
}

/// A row of actions under the copy that explains them, trailing-aligned like a sheet's buttons.
struct SettingsActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { Spacer(minLength: 0); content }
            VStack(alignment: .trailing, spacing: 8) { content }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#if DEBUG
#Preview("Row shapes") {
    @Previewable @State var toggle = true
    @Previewable @State var choice = DockAppVisibility.showAll
    VStack(spacing: SettingsMetrics.cardSpacing) {
        SettingsCard(title: .settingsBehavior, footnote: .behaviorHelp) {
            SettingsToggleRow(title: .behaviorAutoHide, isOn: $toggle)
            SettingsMenuRow(title: .settingsAppVisibility, selection: $choice) {
                ForEach(DockAppVisibility.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
        }
    }
    .padding(24)
    .frame(width: 560)
}
#endif
