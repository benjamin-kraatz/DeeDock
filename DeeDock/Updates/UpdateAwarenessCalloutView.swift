#if DIRECT_DISTRIBUTION
import SwiftUI

/// Lets the panel's owner start the callout's departure from outside the view tree.
@Observable
final class UpdateCalloutPresentation {
    /// True once the callout should fold up and leave. The owner closes the panel after
    /// `UpdateAwarenessCalloutView.departureDuration(reduceMotion:)`.
    var isLeaving = false
}

/// Dismissible main-display callout for a waiting or freshly installed update.
///
/// A bead of Liquid Glass carrying the update mark drops in from under the menu bar, then
/// opens sideways into an island with the copy and actions. Leaving runs the same path
/// backwards. Every animation is one-shot, so a resting callout draws nothing per frame.
/// Reduce Motion fades the finished island in and out in place.
///
/// The island animates inside a transparent canvas (`canvasInsets`), so the hosting panel
/// must not draw a window shadow: AppKit would cache it for the first frame's outline.
struct UpdateAwarenessCalloutView: View {
    enum Kind: Equatable {
        /// A scheduled offer that needs the user to download or approve it.
        case available
        /// A silently downloaded offer that idle install has not reached yet.
        case ready
        /// An automatic install finished. `version` is the running version.
        case installed
    }

    /// Transparent room around the island for its descent, spring overshoot, and shadow.
    static let canvasInsets = EdgeInsets(top: 10, leading: 40, bottom: 48, trailing: 40)

    /// How long the owner keeps the panel after setting `isLeaving`, covering `leave()`.
    static func departureDuration(reduceMotion: Bool) -> Duration {
        .milliseconds(reduceMotion ? 200 : 480)
    }

    private static let width: CGFloat = 468
    private static let inset: CGFloat = 14
    /// The bead wraps the mark with a slimmer margin than the open island.
    private static let beadDiameter = UpdateCalloutMark.diameter + 16

    private enum Stage {
        /// Above the resting position and invisible.
        case away
        /// Landed as a bead that holds only the mark.
        case bead
        /// Opened into the full island.
        case open
    }

    var kind: Kind = .available
    let version: String
    let reduceTransparency: Bool
    var reduceMotion = false
    var presentation = UpdateCalloutPresentation()
    let open: () -> Void
    let dismiss: () -> Void
    @State private var stage = Stage.away

    private var symbol: String {
        switch kind {
        case .available: "arrow.down"
        case .ready: "arrow.clockwise"
        case .installed: "sparkles"
        }
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .available: .updatesAwarenessTitle
        case .ready: .updatesReadyCalloutTitle
        case .installed: .updatesInstalledCalloutTitle
        }
    }

    private var message: LocalizedStringResource {
        switch kind {
        case .available: .updatesAwarenessBody(version: version)
        case .ready: .updatesReadyCalloutBody(version: version)
        case .installed: .updatesInstalledCalloutBody(version: version)
        }
    }

    var body: some View {
        let isOpen = stage == .open
        let isAway = stage == .away
        HStack(spacing: 12) {
            UpdateCalloutMark(symbol: symbol, lit: !isAway || reduceMotion)
                // While the island is a bead the mark sits at its centre; opening carries it
                // to the leading edge. The fixed island width keeps this offset exact.
                .offset(x: isOpen || reduceMotion ? 0 : Self.width / 2 - Self.inset - UpdateCalloutMark.diameter / 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(UpdateCalloutReveal(shown: isOpen, order: 0, reduceMotion: reduceMotion))
            Button(kind == .installed ? .updatesInstalledCalloutOpen : .updatesAwarenessOpen, action: open)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(UpdateAwarenessMark.indigo)
                .modifier(UpdateCalloutReveal(shown: isOpen, order: 1, reduceMotion: reduceMotion))
            Button(.updatesAwarenessDismiss, systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .help(Text(.updatesAwarenessDismiss))
                .modifier(UpdateCalloutReveal(shown: isOpen, order: 2, reduceMotion: reduceMotion))
        }
        .controlSize(.large)
        .padding(.leading, Self.inset)
        .padding(.trailing, Self.inset + 2)
        .padding(.vertical, Self.inset)
        .frame(width: Self.width)
        .allowsHitTesting(isOpen)
        .background {
            UpdateCalloutSurface(reduceTransparency: reduceTransparency,
                                 glow: stage == .bead ? 1 : (isOpen ? 0.45 : 0))
                // Animating the proposal morphs the bead into the island without scaling,
                // so the glass keeps true corners and rim width throughout.
                .frame(maxWidth: isOpen || reduceMotion ? .infinity : Self.beadDiameter,
                       maxHeight: isOpen || reduceMotion ? .infinity : Self.beadDiameter)
        }
        .scaleEffect(isAway && !reduceMotion ? 0.72 : 1, anchor: .top)
        .offset(y: isAway && !reduceMotion ? -34 : 0)
        .opacity(isAway ? 0 : 1)
        .padding(Self.canvasInsets)
        .onExitCommand(perform: dismiss)
        .task(id: presentation.isLeaving) {
            if presentation.isLeaving { await leave() } else { await arrive() }
        }
    }

    private func arrive() async {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.25)) { stage = .open }
            return
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { stage = .bead }
        try? await Task.sleep(for: .milliseconds(340))
        // A departure that starts during the pause cancels this task and owns the stage.
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.56, dampingFraction: 0.84)) { stage = .open }
    }

    private func leave() async {
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.18)) { stage = .away }
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) { stage = .bead }
        try? await Task.sleep(for: .milliseconds(230))
        withAnimation(.easeIn(duration: 0.22)) { stage = .away }
    }
}

/// Indigo-to-coral lens that carries the callout's glyph. It is the bead's only content.
private struct UpdateCalloutMark: View {
    static let diameter: CGFloat = 44

    let symbol: String
    /// False until the bead lands; the glyph then settles into the lens.
    let lit: Bool

    var body: some View {
        Circle()
            .fill(UpdateAwarenessMark.fill)
            .overlay {
                // Top-weighted highlight so the lens reads as lit from the screen edge above.
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(lit ? 1 : 0.4)
                    .opacity(lit ? 1 : 0)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .accessibilityHidden(true)
    }
}

/// Glass body of the callout, with the update gradient along its rim.
///
/// `glow` drives the rim: full while the bead lands, then relaxed to a quiet signature edge.
private struct UpdateCalloutSurface: View {
    let reduceTransparency: Bool
    let glow: Double

    /// Concentric with the mark at the island's single-line height; a bead clamps it to a circle.
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 36, style: .continuous) }

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            } else {
                Color.clear.glassEffect(.regular, in: shape)
            }
        }
        .overlay {
            shape
                .strokeBorder(LinearGradient(colors: [UpdateAwarenessMark.indigo, UpdateAwarenessMark.coral],
                                             startPoint: .leading, endPoint: .trailing),
                              lineWidth: 1.5)
                // The rim cools slowly after the island opens. Scoping the animation to the
                // opacity keeps the rim's geometry on the glass's morph spring; a plain
                // `.animation(_:value:)` here would retime its size and detach it from the glass.
                .animation(.easeOut(duration: glow < 1 ? 1.3 : 0.25)) { $0.opacity(glow) }
        }
    }
}

/// Brings one piece of the island's content into focus as the island opens.
///
/// Pieces follow each other by `order` on the way in and leave together, so the island is
/// empty before it folds back into a bead.
private struct UpdateCalloutReveal: ViewModifier {
    let shown: Bool
    let order: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .offset(y: shown || reduceMotion ? 0 : 5)
            .animation(shown ? .smooth(duration: 0.42).delay(reduceMotion ? 0 : 0.12 + Double(order) * 0.07)
                             : .easeOut(duration: 0.14),
                       value: shown)
    }
}

/// Replays arrival and departure on demand; previews have no panel owner to do it.
private struct UpdateCalloutPreviewStage: View {
    var kind = UpdateAwarenessCalloutView.Kind.available
    var reduceTransparency = false
    var reduceMotion = false
    @State private var presentation = UpdateCalloutPresentation()

    var body: some View {
        VStack(spacing: 0) {
            UpdateAwarenessCalloutView(kind: kind, version: "0.5.0", reduceTransparency: reduceTransparency,
                                       reduceMotion: reduceMotion, presentation: presentation,
                                       open: {}, dismiss: { presentation.isLeaving = true })
            Button(presentation.isLeaving ? "Arrive" : "Leave") { presentation.isLeaving.toggle() }
        }
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.teal.opacity(0.5), .indigo.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

#Preview("Update callout") {
    UpdateCalloutPreviewStage()
}

#Preview("Ready callout, static") {
    UpdateCalloutPreviewStage(kind: .ready, reduceMotion: true)
}

#Preview("Installed callout") {
    UpdateCalloutPreviewStage(kind: .installed)
}

#Preview("Update callout, German opaque") {
    UpdateCalloutPreviewStage(reduceTransparency: true)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
