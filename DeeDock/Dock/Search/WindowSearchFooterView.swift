import SwiftUI

/// Keyboard affordances and the escape hatch to settings.
///
/// The hints use key caps because the shortcuts are the fastest path through search and would be
/// invisible in a plain caption.
struct WindowSearchFooterView: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            hint("↑↓", .windowSearchHintSelect)
            hint("↩", .windowSearchHintOpen)
            hint("esc", .windowSearchHintClose)
            Spacer(minLength: 0)
            Button { openSettings() } label: {
                Label { Text(.windowSearchOpenSettings) } icon: { Image(systemName: "gearshape") }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, WindowSearchStyle.contentPadding)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.windowSearchKeyboardHelp))
    }

    private func hint(_ key: String, _ label: LocalizedStringResource) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: key)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5) }
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
