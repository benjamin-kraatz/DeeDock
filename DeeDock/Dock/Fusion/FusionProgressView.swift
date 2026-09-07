import SwiftUI

/// One restrained transition, with the same source-to-artifact relationship at rest.
struct FusionProgressView: View {
    let sources: [FusionSource]
    let activity: FusionState.Activity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emerged = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(sources) { source in
                FusionAppIcon(bundleIdentifier: source.candidate.bundleIdentifier)
            }
            Image(systemName: "arrow.right").accessibilityHidden(true)
            Image(systemName: "doc.text")
                .font(.title).opacity(emerged || reduceMotion ? 1 : 0.3)
                .scaleEffect(emerged || reduceMotion ? 1 : 0.85)
                .accessibilityHidden(true)
            ProgressView().controlSize(.small)
            Text(label)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { emerged = true }
        }
        .accessibilityElement(children: .combine)
    }

    private var label: LocalizedStringResource {
        switch activity {
        case .discovering: .fusionDiscovering
        case .capturing: .fusionCapturing
        case .generating: .fusionGenerating
        case .saving: .fusionSaving
        }
    }
}
