import SwiftUI

/// One restrained transition, with the same source-to-artifact relationship at rest.
///
/// The strip sits between the body and the footer while work runs, so the tray never has two places
/// that say something is happening, and cancelling is where the progress is.
struct FusionProgressView: View {
    let sources: [FusionSource]
    let activity: FusionState.Activity
    /// `nil` while saving: the commit section cannot be interrupted.
    var cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emerged = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(sources) { source in
                    FusionAppIcon(bundleIdentifier: source.candidate.bundleIdentifier, size: 22)
                        .background(.background, in: .circle)
                }
            }
            Image(systemName: "arrow.right")
                .font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            Image(systemName: "doc.text")
                .font(.body).foregroundStyle(.tint)
                .opacity(emerged || reduceMotion ? 1 : 0.3)
                .scaleEffect(emerged || reduceMotion ? 1 : 0.85)
                .accessibilityHidden(true)
            Text(label).font(.callout).lineLimit(1)
            Spacer(minLength: 8)
            ProgressView().controlSize(.small)
            if let cancel {
                Button(.fusionCancelWork, action: cancel)
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .fusionCard()
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { emerged = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.updatesFrequently)
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
