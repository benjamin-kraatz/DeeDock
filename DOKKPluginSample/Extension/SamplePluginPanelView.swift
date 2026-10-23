// DOKK Sample Plugin: a developer example, never shipped with DOKK. See docs/PLUGINS.md.
// Its copy is plain English on purpose: it is sample code, not part of DOKK's interface.

import SwiftUI

/// The sample's panel content, drawn in the plugin's own process below DOKK's header.
///
/// It has no background of its own, so DOKK's panel glass shows through. It exercises what the
/// contract offers: a badge pushed to the tile, keyboard focus in a hosted text field, a request
/// back to DOKK, and a crash DOKK has to survive.
struct SamplePluginPanelView: View {
    let model: SamplePluginModel
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            Text(verbatim: "Hello from DOKK Sample Plugin")
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: model.badge.formatted())
                .font(.system(size: 40, weight: .bold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(model.badge)))
                .animation(reduceMotion ? nil : .snappy, value: model.badge)
                .accessibilityLabel(Text(verbatim: "Badge \(model.badge)"))
            Text(verbatim: "pid \(ProcessInfo.processInfo.processIdentifier) · \(model.link.connectionCount) connection(s)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            TextField(text: $draft, prompt: Text(verbatim: "Type here to test the keyboard")) {
                Text(verbatim: "Keyboard test")
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 210)
            HStack(spacing: 8) {
                Button { model.bumpBadge() } label: { Text(verbatim: "Bump badge") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button(role: .destructive) { model.crash() } label: { Text(verbatim: "Crash plugin") }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    SamplePluginPanelView(model: .shared)
        .frame(width: 320, height: 226)
}
