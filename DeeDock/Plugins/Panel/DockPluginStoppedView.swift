import SwiftUI

/// The calm, in-place notice a panel shows when its plugin stops: what happened, that DOKK is
/// fine, and Restart. Never an alert.
struct DockPluginStoppedView: View {
    let title: String
    /// Shows a spinner in the button while the plugin starts again.
    let restarting: Bool
    let restart: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.6), in: .circle)
                .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(.pluginPanelStoppedTitle(title))
                .font(.system(size: 13.5, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(.pluginPanelStoppedDetail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Button(action: restart) {
                HStack(spacing: 6) {
                    if restarting {
                        ProgressView().controlSize(.mini)
                    }
                    Text(.pluginPanelRestart)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(restarting)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 250)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Stopped") {
    DockPluginStoppedView(title: "Build Status", restarting: false) {}
        .frame(width: 360, height: 236)
}

#Preview("Restarting, dark") {
    DockPluginStoppedView(title: "A plugin with a rather long name that wraps", restarting: true) {}
        .frame(width: 280, height: 220)
        .preferredColorScheme(.dark)
}
#endif
