import SwiftUI

/// The calm, in-place notice a panel shows when its plugin stops: what happened, that DOKK is
/// fine, and Restart. Never an alert.
///
/// While the plugin starts again the button keeps its accent and shows a spinner in place of
/// going grey, so the notice reads as "working" rather than "unavailable". It stops taking
/// clicks until the plugin answers.
struct DockPluginStoppedView: View {
    let title: String
    /// Shows a spinner in the button while the plugin starts again.
    let restarting: Bool
    let restart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
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
            Button { if !restarting { restart() } } label: {
                HStack(spacing: 6) {
                    if restarting {
                        ProgressView()
                            .controlSize(.mini)
                            // White on the accent fill in both appearances.
                            .colorScheme(.dark)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                    Text(.pluginPanelRestart)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .opacity(restarting ? 0.8 : 1)
            .allowsHitTesting(!restarting)
            .accessibilityValue(restarting ? Text(.pluginStatusStarting) : Text(verbatim: ""))
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.25), value: restarting)
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

#Preview("Restart, toggling") {
    @Previewable @State var restarting = false
    DockPluginStoppedView(title: "Build Status", restarting: restarting) { restarting = true }
        .frame(width: 360, height: 236)
        .onChange(of: restarting) { _, value in
            guard value else { return }
            Task { try? await Task.sleep(for: .seconds(1.5)); restarting = false }
        }
}
#endif
