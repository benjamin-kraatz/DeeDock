import SwiftUI

struct WindowWatchExplanationView: View {
    let explanation: WindowWatchExplanation

    var body: some View {
        if explanation.generating || explanation.text != nil
            || explanation.failed
        {
            VStack(alignment: .leading, spacing: 8) {
                Text(.watchAIHeading).font(.callout.weight(.medium))
                if explanation.generating {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(.watchAIGenerating)
                    }
                } else if let text = explanation.text {
                    Text(verbatim: text).textSelection(.enabled)
                } else {
                    Text(.watchAIFailed)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
        }
    }
}

/// Availability is refreshed when setup becomes visible or the app returns to the foreground.
struct WindowWatchExplanationSetup: View {
    @Bindable var explanation: WindowWatchExplanation
    let locale: Locale
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(.watchAIEnable, isOn: $explanation.enabled)
                .toggleStyle(TrailingSwitchToggleStyle())
                .disabled(explanation.unavailableReason != nil)
            Text(explanation.unavailableReason ?? .watchAIHelp)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { explanation.refreshAvailability(locale: locale) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                explanation.refreshAvailability(locale: locale)
            }
        }
    }
}

#Preview("Explanation") {
    WindowWatchExplanationView(
        explanation: WindowWatchExplanation(
            previewText:
                "The progress bar has disappeared and a completion message is now visible."
        )
    )
    .padding().frame(width: 460)
}

#Preview("Explaining") {
    WindowWatchExplanationView(
        explanation: WindowWatchExplanation(generating: true)
    )
    .padding().frame(width: 460)
}

#Preview("Explanation unavailable · German") {
    WindowWatchExplanationView(
        explanation: WindowWatchExplanation(failed: true)
    )
    .environment(\.locale, Locale(identifier: "de"))
    .padding().frame(width: 460)
}

#Preview("Explanation Setup") {
    WindowWatchExplanationSetup(
        explanation: WindowWatchExplanation(failed: false),
        locale: Locale(identifier: "de"),
    )
    .padding().frame(width: 460)
}
