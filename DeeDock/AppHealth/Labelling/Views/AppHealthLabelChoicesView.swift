import SwiftUI

/// The controls of a labelling question for its current phase: the three answers, the follow-up after
/// Misbehaving, or the thank-you confirmation. Shared by the prompt and the manual picker.
///
/// Phases replace each other in place with a blur cross-fade; Reduce Motion uses a plain, shorter fade.
struct AppHealthLabelChoicesView: View {
    let session: AppHealthLabelSession
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch session.phase {
            case .asking:
                AppHealthAnswerButtons(highlighted: session.highlighted, reduceMotion: reduceMotion,
                                       activate: session.activate)
            case .followUp:
                AppHealthFollowUpChoices(highlighted: session.highlighted, reduceMotion: reduceMotion,
                                         activate: session.activate)
            case .thanks:
                AppHealthThanksView(reduceMotion: reduceMotion)
            }
        }
        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.3), value: session.phase)
    }
}

/// Expected / Misbehaving / Not sure, side by side when they fit, stacked otherwise.
struct AppHealthAnswerButtons: View {
    let highlighted: AppHealthLabelSession.Choice?
    let reduceMotion: Bool
    let activate: (AppHealthLabelSession.Choice) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 6) { buttons }
        }
        .buttonStyle(AppHealthChoiceButtonStyle(reduceMotion: reduceMotion))
    }

    @ViewBuilder private var buttons: some View {
        AppHealthChoiceButton(title: .appHealthAnswerExpected, hint: .appHealthAnswerExpectedHint,
                              isHighlighted: highlighted == .answer(.expected)) { activate(.answer(.expected)) }
        AppHealthChoiceButton(title: .appHealthAnswerMisbehaving, hint: .appHealthAnswerMisbehavingHint,
                              isHighlighted: highlighted == .answer(.misbehaving)) { activate(.answer(.misbehaving)) }
        AppHealthChoiceButton(title: .appHealthAnswerNotSure, hint: .appHealthAnswerNotSureHint,
                              isHighlighted: highlighted == .answer(.notSure)) { activate(.answer(.notSure)) }
    }
}

/// "What seems wrong?" with the four details in a grid and Skip.
struct AppHealthFollowUpChoices: View {
    let highlighted: AppHealthLabelSession.Choice?
    let reduceMotion: Bool
    let activate: (AppHealthLabelSession.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.appHealthFollowUpQuestion)
                .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    detail(.spinning)
                    detail(.memoryGrowing)
                }
                GridRow {
                    detail(.frozen)
                    detail(.drainingBattery)
                }
            }
            .buttonStyle(AppHealthChoiceButtonStyle(reduceMotion: reduceMotion))
            HStack {
                Spacer()
                AppHealthChoiceButton(title: .appHealthFollowUpSkip, hint: .appHealthFollowUpSkipHint,
                                      isHighlighted: highlighted == .skip, borderless: true) { activate(.skip) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ detail: AppHealthAnswerDetail) -> some View {
        AppHealthChoiceButton(title: Self.title(detail), hint: .appHealthDetailHint,
                              isHighlighted: highlighted == .detail(detail), fillsWidth: true) {
            activate(.detail(detail))
        }
    }

    static func title(_ detail: AppHealthAnswerDetail) -> LocalizedStringResource {
        switch detail {
        case .spinning: .appHealthDetailSpinning
        case .memoryGrowing: .appHealthDetailMemoryGrowing
        case .frozen: .appHealthDetailFrozen
        case .drainingBattery: .appHealthDetailDrainingBattery
        }
    }
}

/// One answer or detail button, with a ring in the tint while the keyboard highlights it. The style comes from
/// the enclosing group: tiles for the answers and details, borderless for Skip.
struct AppHealthChoiceButton: View {
    let title: LocalizedStringResource
    let hint: LocalizedStringResource
    let isHighlighted: Bool
    var borderless = false
    var fillsWidth = false
    let action: () -> Void

    private var ring: RoundedRectangle {
        RoundedRectangle(cornerRadius: borderless ? 7 : 10, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .overlay {
            ring.strokeBorder(.tint, lineWidth: 2)
                .padding(-2)
                .opacity(isHighlighted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.1), value: isHighlighted)
        .accessibilityHint(Text(hint))
    }
}

/// The short confirmation after a label is written: a check that draws itself in the tint, then the words.
struct AppHealthThanksView: View {
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        HStack(spacing: 8) {
            AppHealthDrawnCheckmark(drawn: shown)
            Text(.appHealthThanks)
                .font(.subheadline.weight(.medium))
                .opacity(shown ? 1 : 0)
                .offset(x: shown || reduceMotion ? 0 : -4)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(duration: 0.5, bounce: 0.2).delay(0.1)) { shown = true }
            }
        }
    }
}

/// A filled disc in the tint with a white check whose stroke draws from left to right. `drawn` animates it;
/// without an animation in the transaction it simply appears complete.
struct AppHealthDrawnCheckmark: View {
    let drawn: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint)
                .scaleEffect(drawn ? 1 : 0.6)
                .opacity(drawn ? 1 : 0)
            AppHealthCheckmarkShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A check as two strokes: the short leg down to the corner, the long leg up. Trimming draws it in that order.
struct AppHealthCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

#if DEBUG
#Preview("Thanks, drawn") {
    VStack(alignment: .leading, spacing: 12) {
        AppHealthThanksView(reduceMotion: false)
        AppHealthThanksView(reduceMotion: true)
        HStack(spacing: 12) {
            AppHealthDrawnCheckmark(drawn: false)
            AppHealthDrawnCheckmark(drawn: true)
            AppHealthDrawnCheckmark(drawn: true, size: 44)
        }
    }
    .tint(SettingsPage.appHealth.tint)
    .padding(16)
    .frame(width: 300)
    .appHealthSurface(opaque: false)
    .padding()
}
#endif
