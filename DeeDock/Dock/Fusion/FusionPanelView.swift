import SwiftUI

struct FusionPanelView: View {
    @Bindable var state: FusionState
    let close: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.fusionTitle).font(.title2.bold())
                Spacer()
                Button(.fusionHide, action: close).disabled(state.activity == .saving)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(.fusionLimitations).font(.callout).foregroundStyle(.secondary)
                    if let draft = state.draft {
                        FusionDraftView(state: state, draft: draft)
                    } else {
                        FusionSelectionView(state: state)
                        if state.hasCapture { FusionInputReviewView(state: state) }
                    }
                    if let activity = state.activity {
                        FusionProgressView(sources: state.sources, activity: activity)
                        if activity != .saving {
                            Button(.fusionCancelWork) { state.cancelWork() }
                        }
                    }
                    if let error = state.error {
                        Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(.fusionDiscard, role: .destructive) { state.reset() }
                    .disabled(state.activity == .saving)
                Spacer()
                if state.draft == nil {
                    Button(.fusionCapture) { state.capture() }
                        .disabled(state.sources.count != 2 || state.isBusy)
                }
            }
        }
        .padding(20)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
        .frame(minWidth: 440, idealWidth: 600, minHeight: 430, idealHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.expireIfNeeded()
        }
    }
}


#if DEBUG
#Preview("Fusion input review") {
    FusionPanelView(state: .preview(), close: {}).frame(width: 600, height: 720)
}
#Preview("Fusion retained draft after save failure") {
    FusionPanelView(state: .preview(failedSave: true), close: {}).frame(width: 600, height: 720)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
