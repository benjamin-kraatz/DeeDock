import SwiftUI

/// The automatic prompt's content: header and label choices on Liquid Glass, with the expiry ring on the close
/// button.
///
/// Reports its natural size through `sizeChanged`, so the panel can follow phase changes. The card sits against
/// the side of the window that touches the dock (`attachedEdge`), so while the window animates to a new height
/// the card stays put at the dock and unfolds away from it. On appear the card grows in from that side with a
/// small spring. Reduce Motion and Reduce Transparency come from the environment; previews pass `overrides`
/// instead, because those environment keys cannot be written on this SDK.
struct AppHealthPromptView: View {
    static let width: CGFloat = 340

    let session: AppHealthLabelSession
    var overrides: AppHealthAccessibilityOverrides?
    /// The dock edge the prompt rises from; nil for the screen-corner fallback, which grows up from the bottom.
    var attachedEdge: DockEdge?
    let sizeChanged: (CGSize) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var environmentReduceTransparency

    init(session: AppHealthLabelSession, overrides: AppHealthAccessibilityOverrides? = nil,
         attachedEdge: DockEdge? = nil, sizeChanged: @escaping (CGSize) -> Void = { _ in }) {
        self.session = session
        self.overrides = overrides
        self.attachedEdge = attachedEdge
        self.sizeChanged = sizeChanged
    }

    var body: some View {
        AppHealthQuestionContent(session: session, reduceMotion: reduceMotion, perform: menu)
            .padding(16)
            .frame(width: Self.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .appHealthSurface(opaque: reduceTransparency)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { sizeChanged($0) }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94, anchor: Self.origin(of: attachedEdge))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(of: attachedEdge))
            .tint(SettingsPage.appHealth.tint)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { appeared = true }
            }
    }

    private var reduceMotion: Bool { overrides?.reduceMotion ?? environmentReduceMotion }
    private var reduceTransparency: Bool { overrides?.reduceTransparency ?? environmentReduceTransparency }

    /// The "…" menu only belongs to automatic prompts.
    private var menu: ((AppHealthLabelSession.MenuCommand) -> Void)? {
        guard session.source == .prompt else { return nil }
        let session = session
        return { session.perform($0) }
    }

    /// Where the card stays while the window resizes: the dock's side. Left and right docks centre the prompt on
    /// the tile, so there the card keeps its middle.
    static func alignment(of edge: DockEdge?) -> Alignment {
        switch edge {
        case .bottom, nil: .bottom
        case .top: .top
        case .left, .right: .center
        }
    }

    /// The point the entrance grows from, on the dock's side.
    static func origin(of edge: DockEdge?) -> UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        case nil: .bottomTrailing
        }
    }
}

/// Header and choices. The picker shows the same content for a picked app.
struct AppHealthQuestionContent: View {
    let session: AppHealthLabelSession
    let reduceMotion: Bool
    let perform: ((AppHealthLabelSession.MenuCommand) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppHealthQuestionHeader(app: session.app, reason: session.reason,
                                    expiry: session.phase == .asking ? session.expiry : nil,
                                    perform: perform, close: session.dismiss, reduceMotion: reduceMotion)
            AppHealthLabelChoicesView(session: session, reduceMotion: reduceMotion)
        }
    }
}

/// The rounded surface of a labelling panel: Liquid Glass, or an opaque window background with a hairline
/// with Reduce Transparency. The glass is applied to the content itself, which keeps the content in front of it.
struct AppHealthSurface: ViewModifier {
    let opaque: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    func body(content: Content) -> some View {
        if opaque {
            content
                .background { shape.fill(Color(nsColor: .windowBackgroundColor)) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
        } else {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// Puts a labelling panel's content on its surface.
    func appHealthSurface(opaque: Bool) -> some View {
        modifier(AppHealthSurface(opaque: opaque))
    }
}

/// Stand-ins for Reduce Motion and Reduce Transparency in previews. Production passes nil and reads the
/// environment.
struct AppHealthAccessibilityOverrides {
    var reduceMotion = false
    var reduceTransparency = false
}

#if DEBUG
#Preview("Spin in the background") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.cpu, .background])), attachedEdge: .bottom)
        .padding()
}

#Preview("Spin while away") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.cpu, .idleUser])), attachedEdge: .bottom)
        .padding()
}

#Preview("Memory growth") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.memory])), attachedEdge: .bottom)
        .padding()
}

#Preview("Wake-ups") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.background, .wakeups])), attachedEdge: .left)
        .padding()
}

#Preview("Hang") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.hang])), attachedEdge: .bottom)
        .padding()
}

#Preview("Ordinary") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([], trigger: .ordinary)), attachedEdge: .bottom)
        .padding()
}

#Preview("Follow-up") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.cpu, .background]), phase: .followUp), attachedEdge: .bottom)
        .padding()
}

#Preview("Thanks") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.memory]), phase: .thanks), attachedEdge: .bottom)
        .padding()
}

#Preview("Long name, German, dark") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        app: AppHealthLabellingPreviewData.longNamedApp,
        reason: AppHealthLabellingPreviewData.reason([.cpu, .idleUser])), attachedEdge: .bottom)
        .padding()
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}

#Preview("Reduce Motion and Transparency, dark") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.hang])),
        overrides: AppHealthAccessibilityOverrides(reduceMotion: true, reduceTransparency: true),
        attachedEdge: .bottom)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Reduce Transparency, follow-up, light") {
    AppHealthPromptView(session: AppHealthLabellingPreviewData.session(
        reason: AppHealthLabellingPreviewData.reason([.memory]), phase: .followUp),
        overrides: AppHealthAccessibilityOverrides(reduceMotion: false, reduceTransparency: true),
        attachedEdge: .bottom)
        .padding()
        .preferredColorScheme(.light)
}
#endif
