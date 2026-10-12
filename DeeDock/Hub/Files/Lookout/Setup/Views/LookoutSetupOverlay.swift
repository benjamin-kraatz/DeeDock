import SwiftUI

/// Lookout's onboarding over the Hub (the mockup's `#veil` and `.sheet`): a dimming veil over the header and the tab,
/// and the card 48 pt below the Hub's top edge.
///
/// The card pops in (scale 96 % and 10 pt low to rest, 0.32 s, `cubic-bezier(.2,1.1,.3,1)`), or fades in under
/// Reduce Motion. A click on the veil does nothing, as in the mockup: the card closes with "Not now" or Escape.
/// `HubCoordinator` shows this only while `LookoutSetupCoordinator.isPresented`.
struct LookoutSetupOverlay: View {
    let setup: LookoutSetupCoordinator
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @State private var shown = false

    static let pop = Animation.timingCurve(0.2, 1.1, 0.3, 1, duration: 0.32)
    static let topInset: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.28)
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
                LookoutSetupSheet(setup: setup, maxHeight: proxy.size.height - Self.topInset - 24,
                                  reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.96)
                    .offset(y: shown || reduceMotion ? 0 : 10)
                    .opacity(shown ? 1 : 0)
                    .padding(.top, Self.topInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.pop) { shown = true }
        }
    }
}

/// The card: the current step over its footer.
struct LookoutSetupSheet: View {
    let setup: LookoutSetupCoordinator
    /// The tallest the card may grow in the Hub; its step scrolls beyond that.
    var maxHeight: CGFloat = .infinity
    var reduceMotion = false
    var reduceTransparency = false

    static let width: CGFloat = 640
    static let minimumHeight: CGFloat = 470
    static let footerHeight: CGFloat = 61

    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let bodyHeight = min(max(contentHeight, min(Self.minimumHeight, maxHeight) - Self.footerHeight),
                             max(maxHeight - Self.footerHeight, 120))
        VStack(spacing: 0) {
            ScrollView {
                LookoutSetupStepContent(setup: setup, reduceMotion: reduceMotion)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            .frame(height: bodyHeight)
            LookoutSetupFooter(setup: setup, reduceMotion: reduceMotion)
        }
        .frame(width: Self.width)
        .background { LookoutSetupSheetBackground(shape: shape, opaque: reduceTransparency) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(LookoutTheme(scheme).strongLine, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.35), radius: 40, y: 24)
        .animation(reduceMotion ? nil : HubStyle.motion, value: bodyHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.lookoutSetupAccessibilityLabel))
        .accessibilityAddTraits(.isModal)
    }
}

/// A frosted card over the Hub's glass (the mockup's `--sheet`), opaque under Reduce Transparency.
private struct LookoutSetupSheetBackground: View {
    let shape: RoundedRectangle
    let opaque: Bool

    var body: some View {
        if opaque {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

/// The current step, sliding 26 pt in from the side it was reached from (0.32 s, `cubic-bezier(.2,.9,.25,1)`); the
/// step it replaces leaves at once, as in the mockup. Reduce Motion crossfades instead.
private struct LookoutSetupStepContent: View {
    let setup: LookoutSetupCoordinator
    let reduceMotion: Bool

    static let slide = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.32)

    var body: some View {
        let step = setup.draft.step
        let offset = reduceMotion ? 0 : 26 * setup.direction.sign
        ZStack(alignment: .topLeading) {
            LookoutSetupStepView(setup: setup, step: step, reduceMotion: reduceMotion)
                .id(step)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: offset)), removal: .identity))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : Self.slide, value: step)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 28, leading: 34, bottom: 10, trailing: 34))
    }
}

/// One step's view, bound to the coordinator's actions.
private struct LookoutSetupStepView: View {
    let setup: LookoutSetupCoordinator
    let step: LookoutSetupStep
    let reduceMotion: Bool

    var body: some View {
        switch step {
        case .welcome:
            LookoutSetupWelcomeStep()
        case .folders:
            LookoutSetupFoldersStep(draft: setup.draft, setChosen: { setup.setChosen($0, $1) },
                                    addFolder: { setup.addFolder() })
        case .access:
            LookoutSetupAccessStep(draft: setup.draft, requestAccess: { setup.requestAccess($0) },
                                   openSettings: { setup.openPrivacySettings() })
        case .download:
            LookoutSetupDownloadStep(downloader: setup.downloader, indexOnBattery: setup.draft.indexOnBattery,
                                     setIndexOnBattery: { setup.setIndexOnBattery($0) })
        case .firstPass:
            LookoutSetupFirstPassStep(progress: setup.firstPassProgress, current: setup.engine.indexStatus?.current,
                                      reduceMotion: reduceMotion, initialFeed: setup.previewFeed)
        }
    }
}

/// The progress dots and the step's buttons (the mockup's `.ft`).
private struct LookoutSetupFooter: View {
    let setup: LookoutSetupCoordinator
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let step = setup.draft.step
        HStack(spacing: 10) {
            LookoutSetupDots(step: step, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch step {
            case .welcome:
                Button(.lookoutSetupNotNow) { setup.close() }
                    .buttonStyle(.lookoutSecondary)
                Button(.lookoutSetupContinue) { setup.continueStep() }
                    .buttonStyle(.lookoutPrimary)
            case .folders, .access, .download:
                Button(.lookoutSetupBack) { setup.goBack() }
                    .buttonStyle(.lookoutSecondary)
                Button(.lookoutSetupContinue) { setup.continueStep() }
                    .buttonStyle(.lookoutPrimary)
                    .disabled(!setup.canContinue)
            case .firstPass:
                Button(.lookoutSetupFinishLater) { setup.finish(startSearching: false) }
                    .buttonStyle(.lookoutSecondary)
                Button(.lookoutSetupStartSearching) { setup.finish(startSearching: true) }
                    .buttonStyle(.lookoutPrimary)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: LookoutSetupSheet.footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(height: 0.5)
        }
    }
}

/// Five dots; the current one widens to 18 pt in the Lookout accent (the mockup's `.dots`).
private struct LookoutSetupDots: View {
    let step: LookoutSetupStep
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(LookoutSetupStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? LookoutTheme(scheme).accent : HubFilesTheme(scheme).chipHighlight)
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text(.lookoutSetupStepOf(step.rawValue + 1, LookoutSetupStep.allCases.count)))
    }
}
