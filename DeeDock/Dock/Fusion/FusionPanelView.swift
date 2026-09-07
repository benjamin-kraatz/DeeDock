import SwiftUI

/// The App Fusion tray: choose two windows, review what was actually captured, then keep the result.
///
/// Every step shares one skeleton — a header carrying the step indicator, a scrolling body of
/// labelled cards, and a footer bar holding that step's single primary action — so moving through
/// the flow never re-flows the window and the button that continues is always in the same place.
struct FusionPanelView: View {
    @Bindable var state: FusionState
    let close: () -> Void
    /// Previews only: exercises the opaque appearance without a system accessibility setting.
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: FusionMotion { FusionMotion(enabled: !reduceMotion) }

    /// 0 while choosing windows, 1 once both are captured, 2 once a draft exists.
    private var step: Int {
        if state.draft != nil { return 2 }
        return state.hasCapture ? 1 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: FusionMetrics.section) {
                    if let error = state.error {
                        FusionNotice(Text(verbatim: error), tone: .warning)
                            .textSelection(.enabled)
                            .accessibilityAddTraits(.updatesFrequently)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if let draft = state.draft {
                        FusionDraftView(state: state, draft: draft)
                    } else {
                        FusionSelectionView(state: state)
                        if state.hasCapture { FusionInputReviewView(state: state) }
                    }
                    FusionNotice(.fusionLimitations, title: .fusionLimitationsTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FusionMetrics.page)
            }
            if let activity = state.activity {
                FusionProgressView(sources: state.sources, activity: activity,
                                   cancel: activity == .saving ? nil : { state.cancelWork() })
                    .padding(.horizontal, FusionMetrics.page)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            footer
        }
        .animation(motion.step, value: step)
        .animation(motion.step, value: state.activity)
        .animation(motion.step, value: state.error)
        .environment(\.fusionMotion, motion)
        .background(reduceTransparency || forceOpaqueBackground
                    ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                    : AnyShapeStyle(.regularMaterial))
        .frame(minWidth: 460, idealWidth: 620, minHeight: 460, idealHeight: 720)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.fusionTitle))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.expireIfNeeded()
        }
    }

    // MARK: - Header

    /// The window's own title bar already names the tray, so the header carries progress instead.
    private var header: some View {
        HStack(spacing: 12) {
            FusionFlowSteps(current: step)
            Spacer(minLength: 8)
            Button(.fusionHide, action: close)
                .buttonStyle(.borderless).controlSize(.small)
                .foregroundStyle(.secondary)
                .disabled(state.activity == .saving)
        }
        .padding(.horizontal, FusionMetrics.footerHorizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) { state.reset() } label: {
                Label(.fusionDiscard, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(state.activity == .saving)
            Spacer(minLength: 12)
            primaryAction
        }
        .fusionFooterBar()
    }

    /// One button per step, always in the same corner: capture, generate, then save.
    @ViewBuilder private var primaryAction: some View {
        if state.draft != nil {
            if let url = state.savedURL {
                Button(.fusionOpenArtifact, systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(.fusionSave, systemImage: "tray.and.arrow.down") { state.save() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.isBusy || state.draft?.isValid != true)
            }
        } else if state.hasCapture {
            Button(.fusionGenerate, systemImage: "sparkles") { state.generate() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canGenerate)
        } else {
            Button(.fusionCapture, systemImage: "text.viewfinder") { state.capture() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(state.sources.count != 2 || state.isBusy)
        }
    }
}

#if DEBUG
#Preview("Fusion input review") {
    FusionPanelView(state: .preview(), close: {}).frame(width: 620, height: 720)
}
#Preview("Fusion selection") {
    FusionPanelView(state: .preview(captured: false), close: {}).frame(width: 620, height: 720)
}
#Preview("Fusion retained draft after save failure") {
    FusionPanelView(state: .preview(failedSave: true), close: {}).frame(width: 620, height: 720)
        .environment(\.locale, Locale(identifier: "de"))
}
#Preview("Fusion — Reduce Transparency") {
    FusionPanelView(state: .preview(), close: {}, forceOpaqueBackground: true)
        .frame(width: 620, height: 720)
}
#endif
