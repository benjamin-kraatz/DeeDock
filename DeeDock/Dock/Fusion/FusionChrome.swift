import SwiftUI

/// Shared furniture for the App Fusion tray.
///
/// The tray is a three-step flow — choose, review, result — and every step is built from the same
/// three pieces so a step change never re-flows the window: a header carrying the step indicator, a
/// scrolling body of labelled cards, and a footer bar holding that step's one primary action.
/// Keeping the metrics and surfaces here stops each step from inventing its own padding.
///
/// The values deliberately match `CapsuleMetrics` and the Session Capsules panel: both are
/// checkpoint flows over captured windows, and they should read as one app rather than two.
enum FusionMetrics {
    /// Outer padding of a scrolling step body.
    static let page: CGFloat = 18
    /// Space between labelled sections.
    static let section: CGFloat = 18
    static let cardRadius: CGFloat = 10
    static let footerHorizontal: CGFloat = 16
    static let footerVertical: CGFloat = 12
}

/// Tray-wide motion, disabled as one when the system asks for reduced motion.
struct FusionMotion {
    let enabled: Bool

    /// Step-to-step navigation.
    var step: Animation? { enabled ? .smooth(duration: 0.32) : nil }
    /// Hover and press feedback.
    var hover: Animation? { enabled ? .easeOut(duration: 0.14) : nil }
    /// Selection and other direct manipulation.
    var pop: Animation? { enabled ? .snappy(duration: 0.22, extraBounce: 0.12) : nil }
}

private struct FusionMotionKey: EnvironmentKey {
    static let defaultValue = FusionMotion(enabled: true)
}

extension EnvironmentValues {
    var fusionMotion: FusionMotion {
        get { self[FusionMotionKey.self] }
        set { self[FusionMotionKey.self] = newValue }
    }
}

// MARK: - Surfaces

extension View {
    /// The tray's one card surface: a faint fill and a hairline border, no shadow and no gradient.
    /// `emphasized` marks a card that holds an editable field rather than plain reading text.
    func fusionCard(emphasized: Bool = false, radius: CGFloat = FusionMetrics.cardRadius) -> some View {
        background(.quaternary.opacity(emphasized ? 0.55 : 0.35), in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(.quaternary, lineWidth: 1)
            }
    }

    /// The step footer: one divider and one row of controls, identical on every step.
    func fusionFooterBar() -> some View {
        VStack(spacing: 0) {
            Divider()
            self
                .padding(.horizontal, FusionMetrics.footerHorizontal)
                .padding(.vertical, FusionMetrics.footerVertical)
        }
    }
}

/// Row button style: the card lifts under the pointer and settles under a click.
struct FusionRowButtonStyle: ButtonStyle {
    @Environment(\.fusionMotion) private var motion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering && !configuration.isPressed ? 0.04 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(motion.hover, value: hovering)
            .animation(motion.hover, value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

// MARK: - Sections

/// A labelled section: a small symbol, a heading, an optional trailing control, then the content.
///
/// Headings carry the structure the tray used to leave to plain bold text, so a long step reads as
/// a few named parts instead of one column of paragraphs.
struct FusionSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringResource
    let symbol: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension FusionSection where Accessory == EmptyView {
    init(_ title: LocalizedStringResource, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

extension FusionSection {
    init(_ title: LocalizedStringResource, symbol: String,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: accessory, content: content)
    }
}

// MARK: - Notices

/// Guidance and problems, in the tray rather than as an alert so the flow stays put.
///
/// One shape for all three tones keeps the tray quiet: only the symbol and a low-opacity tint
/// separate a hint from a warning.
struct FusionNotice: View {
    enum Tone { case info, warning, success }

    let tone: Tone
    var title: LocalizedStringResource?
    let message: Text

    init(_ message: LocalizedStringResource, tone: Tone = .info, title: LocalizedStringResource? = nil) {
        self.init(Text(message), tone: tone, title: title)
    }

    init(_ message: Text, tone: Tone = .info, title: LocalizedStringResource? = nil) {
        self.message = message
        self.tone = tone
        self.title = title
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption).foregroundStyle(accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).font(.caption.weight(.semibold))
                }
                message
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(accent.opacity(tone == .info ? 0.07 : 0.12), in: .rect(cornerRadius: FusionMetrics.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: FusionMetrics.cardRadius)
                .strokeBorder(accent.opacity(tone == .info ? 0.18 : 0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch tone {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    private var accent: Color {
        switch tone {
        case .info: .secondary
        case .warning: .yellow
        case .success: .green
        }
    }
}

// MARK: - Flow steps

/// Where the user is in the three-step flow, and where they are going next.
struct FusionFlowSteps: View {
    /// 0 while choosing windows, 1 while reviewing captured input, 2 once a draft exists.
    let current: Int
    @Environment(\.fusionMotion) private var motion

    private static let titles: [LocalizedStringResource] = [.fusionStepSelect, .fusionStepReview, .fusionStepResult]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.titles.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Capsule().fill(.quaternary).frame(width: 10, height: 1.5)
                }
                step(title, index: index)
            }
        }
        .animation(motion.pop, value: current)
        .accessibilityElement(children: .combine)
    }

    private func step(_ title: LocalizedStringResource, index: Int) -> some View {
        let done = index < current
        let active = index == current
        return HStack(spacing: 4) {
            ZStack {
                Circle().fill(active || done ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 12, height: 12)
            Text(title)
                .font(.caption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}

#if DEBUG
#Preview("Fusion chrome") {
    VStack(alignment: .leading, spacing: FusionMetrics.section) {
        FusionFlowSteps(current: 1)
        FusionSection(.fusionSelectionTitle, symbol: "macwindow.on.rectangle") {
            Text(verbatim: "Card content").frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).fusionCard()
        }
        FusionNotice(.fusionSelectionHelp)
        FusionNotice(.fusionExpired, tone: .warning)
        FusionNotice(.fusionSaved, tone: .success)
    }
    .padding(FusionMetrics.page)
    .frame(width: 520)
}
#endif
