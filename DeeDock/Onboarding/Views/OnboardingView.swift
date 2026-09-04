import SwiftUI

/// The first-launch tour.
///
/// One page at a time: a demonstration on top, a short explanation under it, and a footer that
/// never moves. Only the page between them is replaced, so the window is a stable frame a person
/// reads through rather than a sequence of differently shaped screens.
struct OnboardingView: View {
    let store: OnboardingStore
    let systemDock: SystemDockMonitor
    let loginItems: LoginItemController
    /// Shared dock defaults. The tour reads the current edge so the placement page opens on
    /// what a person already has, and that page is the only thing in the tour that writes.
    let settings: DockSettingsStore
    /// Runs beside the system Settings link so the completed tour can close itself.
    var settingsSelected: () -> Void = {}
    /// Ends the tour, which the owning window controller turns into a close.
    var finish: () -> Void = {}
    /// Previews pass explicit values; the tour otherwise follows the system settings. Both are
    /// threaded into the stages, which cannot read a preview's environment override themselves.
    var reduceMotionOverride: Bool? = nil
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var step: OnboardingStep { store.step }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                // Pages are sized to fit the window, but the final page's login card grows with
                // approval and error states, so overflow scrolls rather than clipping.
                ScrollView(.vertical) {
                    page(for: step)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            OnboardingFooter(step: step, total: store.totalSteps, canGoBack: store.canGoBack,
                             isFinalStep: store.isFinalStep,
                             back: { withAnimation(pageAnimation) { store.goBack() } },
                             skip: { withAnimation(pageAnimation) { store.skip() } },
                             advance: advance,
                             settingsSelected: settingsSelected)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { wash }
        // The tour is decorative until a step needs live state; only these two steps do.
        .onAppear { systemDock.start(); loginItems.refresh() }
        .onDisappear { systemDock.stop() }
    }

    /// A breath of the step's identity color behind the whole page, matching the wash the
    /// Settings detail pane draws, so the two windows look like one product.
    private var wash: some View {
        LinearGradient(colors: [step.tint.opacity(0.12), .clear], startPoint: .top, endPoint: .center)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: step)
            .ignoresSafeArea()
    }

    private var pageAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.32) }

    /// Content leaves the way it came: forward moves push the page left, back moves push right.
    /// Reduce Motion crossfades instead, matching `SettingsDetailView`.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = store.isMovingForward ? 22 : -22
        return .asymmetric(insertion: .offset(x: distance).combined(with: .opacity),
                           removal: .offset(x: -distance).combined(with: .opacity))
    }

    private func advance() {
        var reachedEnd = false
        withAnimation(pageAnimation) { reachedEnd = store.advance() }
        if reachedEnd { finish() }
    }

    @ViewBuilder private func page(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            standard(step) { OnboardingWelcomeStage(reduceMotionOverride: reduceMotionOverride) }
        case .systemDock:
            VStack(alignment: .leading, spacing: 18) {
                stage(step) {
                    OnboardingSystemDockStage(reservesSpace: systemDock.reservesSpace,
                                              reduceMotionOverride: reduceMotionOverride)
                }
                heading(step, includeSummary: false)
                OnboardingSystemDockGuide(reservesSpace: systemDock.reservesSpace,
                                          openSettings: systemDock.openDesktopAndDockSettings)
            }
        case .placement:
            standard(step, prompt: .onboardingPlacementPrompt) {
                OnboardingPlacementPicker(edge: settings.value.edge,
                                          select: { settings.update(\.edge, to: $0) },
                                          reduceMotionOverride: reduceMotionOverride)
            }
        case .appearance:
            standard(step) { OnboardingAppearanceStage(reduceMotionOverride: reduceMotionOverride) }
        case .hiding:
            standard(step) { OnboardingHidingStage(reduceMotionOverride: reduceMotionOverride) }
        case .displays:
            standard(step) { OnboardingDisplaysStage(reduceMotionOverride: reduceMotionOverride) }
        case .ready:
            VStack(alignment: .leading, spacing: 20) {
                heading(step, includeSummary: true)
                OnboardingFinalStep(loginStatus: loginItems.status,
                                    pendingOperation: loginItems.pendingOperation,
                                    loginError: loginItems.errorMessage,
                                    setLoginEnabled: { loginItems.setEnabled($0) },
                                    cancelLoginRequest: { loginItems.cancelRequest() },
                                    refreshLogin: loginItems.refresh,
                                    openLoginSettings: loginItems.openSystemSettings,
                                    dismissLoginError: loginItems.dismissError)
            }
        }
    }

    /// The shape almost every page takes: a stage, then a title and a sentence.
    ///
    /// A `prompt` marks the stage as one a person can operate. Pass it only for pages that
    /// really do change something — its absence is what identifies a demonstration.
    private func standard<Content: View>(_ step: OnboardingStep, prompt: LocalizedStringResource? = nil,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stage(step, content: content)
            if let prompt {
                OnboardingPrompt(text: prompt, tint: step.tint)
                    .padding(.leading, 2)
            }
            heading(step, includeSummary: true).padding(.top, 6)
        }
    }

    private func stage<Content: View>(_ step: OnboardingStep,
                                      @ViewBuilder content: () -> Content) -> some View {
        OnboardingStage(tint: step.tint, reduceTransparencyOverride: reduceTransparencyOverride,
                        content: content)
    }

    private func heading(_ step: OnboardingStep, includeSummary: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(glyph: step.glyph, colors: step.tileColors, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if includeSummary {
                    Text(step.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
/// Preview composition uses scratch preferences and a stub service, so nothing here registers
/// a login item or writes the real onboarding record.
enum OnboardingPreview {
    static func store() -> OnboardingStore {
        OnboardingStore(repository: OnboardingRepository(defaults: UserDefaults(suiteName: "preview.onboarding")!))
    }

    static func monitor(reservesSpace: Bool) -> SystemDockMonitor {
        SystemDockMonitor(screens: {
            let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
            let visible = reservesSpace
                ? CGRect(x: 0, y: 70, width: 1440, height: 806)
                : CGRect(x: 0, y: 0, width: 1440, height: 876)
            return [(frame, visible)]
        })
    }

    @MainActor static func view(step: OnboardingStep, reservesSpace: Bool = true,
                                reduceMotion: Bool? = nil, reduceTransparency: Bool? = nil) -> some View {
        let store = store()
        while store.step != step { _ = store.advance() }
        return OnboardingView(store: store, systemDock: monitor(reservesSpace: reservesSpace),
                              loginItems: LoginItemPreview.controller(),
                              settings: DockSettingsStore(repository: nil),
                              reduceMotionOverride: reduceMotion,
                              reduceTransparencyOverride: reduceTransparency)
            .frame(width: OnboardingWindowMetrics.size.width, height: OnboardingWindowMetrics.size.height)
    }
}

#Preview("Tour — welcome") { OnboardingPreview.view(step: .welcome) }
#Preview("Tour — hide the macOS Dock") { OnboardingPreview.view(step: .systemDock) }
#Preview("Tour — placement, dark") { OnboardingPreview.view(step: .placement).preferredColorScheme(.dark) }
#Preview("Tour — appearance") { OnboardingPreview.view(step: .appearance) }
#Preview("Tour — auto-hide") { OnboardingPreview.view(step: .hiding) }
#Preview("Tour — displays") { OnboardingPreview.view(step: .displays) }
#Preview("Tour — ready") { OnboardingPreview.view(step: .ready) }
#Preview("Tour — Reduce Motion") { OnboardingPreview.view(step: .placement, reduceMotion: true) }
#Preview("Tour — Reduce Transparency") {
    OnboardingPreview.view(step: .welcome, reduceTransparency: true)
}
#endif
