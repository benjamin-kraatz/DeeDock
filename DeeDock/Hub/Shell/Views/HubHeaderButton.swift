import SwiftUI

/// A 32-point icon button in the Hub header (pin, close) with a hover chip, press feedback, and a
/// tooltip. A symbol change (pin to pin.slash) replaces the glyph with a symbol effect.
struct HubHeaderButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14.5, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(hovered ? (colorScheme == .dark ? 0.07 : 0.05) : 0),
                            in: .rect(cornerRadius: 9, style: .continuous))
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.hubPress(scale: 0.9))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

#Preview("Header buttons") {
    HStack(spacing: 6) {
        HubHeaderButton(symbol: "pin", label: .hubPinHelp) {}
        HubHeaderButton(symbol: "pin.slash", label: .hubAttachHelp) {}
        HubHeaderButton(symbol: "xmark", label: .hubCloseHelp) {}
    }
    .padding(24)
}
