#if DIRECT_DISTRIBUTION
import SwiftUI

/// The one surface for DOKK updates: a compact callout and the full update panel.
///
/// A bead of Liquid Glass carrying the update mark drops in from under the menu bar, then
/// opens into an island. As a callout the island is a single row. As the panel the same
/// glass grows to hold the phase's details and actions. Leaving runs the arrival backwards.
///
/// There is exactly one glass shape, and it is the island's real layout: a bead holds only
/// the mark, and opening inserts the rest. Content appears at its final position and the
/// growing glass uncovers it, so nothing slides or reflows mid-morph. Every animation is
/// one-shot; a resting island draws nothing per frame. Reduce Motion fades the finished
/// island in place.
///
/// Rendering never starts a check or answers a Sparkle callback. The island animates inside
/// a transparent canvas (`canvasInsets`), so the hosting panel must not draw a window
/// shadow: AppKit would cache it for the first frame's outline.
struct UpdateIslandView: View {
    /// Transparent room around the island for its descent, spring overshoot, and shadow.
    static let canvasInsets = EdgeInsets(top: 10, leading: 40, bottom: 48, trailing: 40)
    static let calloutWidth: CGFloat = 468
    static let panelWidth: CGFloat = 560
    /// Tallest callout the owner's canvas must hold: the row with a message of four lines.
    static let calloutMaxHeight: CGFloat = 132

    /// How long the owner keeps the panel after setting `isLeaving`, covering `leave()`.
    static func departureDuration(reduceMotion: Bool) -> Duration {
        .milliseconds(reduceMotion ? 200 : 520)
    }

    private static let inset: CGFloat = 14
    /// The bead wraps the mark with a slimmer margin than the open island.
    private static let beadInset: CGFloat = 8

    private enum Stage {
        /// Above the resting position and invisible.
        case away
        /// Landed as a bead that holds only the mark.
        case bead
        /// Opened into the island.
        case open
    }

    let model: UpdateIslandModel
    let presentation: UpdatePresentation
    var awareness: UpdateAwarenessStore? = nil
    let reduceTransparency: Bool
    var reduceMotion = false
    /// The callout's primary button.
    var openCallout: () -> Void = {}
    var dismissCallout: () -> Void = {}
    /// A panel action with the callback generation it was rendered for.
    var action: (UpdateAction, UUID) -> Void = { _, _ in }
    /// The panel's close button and Escape. The owner applies its phase policy.
    var close: () -> Void = {}
    @State private var stage = Stage.away

    private var isPanel: Bool { model.content == .panel }

    private var calloutKind: UpdateIslandAnnouncement.Kind? {
        if case .callout(let announcement) = model.content { announcement.kind } else { nil }
    }

    private var symbol: String {
        switch calloutKind {
        case .available: "arrow.down"
        case .ready: "arrow.clockwise"
        case .installed: "sparkles"
        case nil: presentation.symbol
        }
    }

    /// Phases that put content under the header.
    private var hasDetails: Bool {
        presentation.diagnostic != nil || ![.idle, .notFound, .installed].contains(presentation.phase)
    }

    /// One critically damped spring for every size change of an open island. A large sheet
    /// of glass that overshoots reads as wobble, so only the small bead is allowed to bounce.
    private var morph: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 1)
    }

    /// Content materialises shortly after the glass starts to open, in `order`, and is gone
    /// before the glass has closed over it.
    private func reveal(_ order: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: AnyTransition(.blurReplace)
                .animation(.smooth(duration: 0.38).delay(0.12 + Double(order) * 0.05)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    var body: some View {
        let isAway = stage == .away
        // Reduce Motion skips the bead: the finished island fades in place.
        let isOpen = stage == .open || reduceMotion
        let showsBody = isPanel && isOpen
        VStack(alignment: .leading, spacing: Self.inset) {
            HStack(spacing: 12) {
                UpdateIslandMark(symbol: symbol, lit: !isAway || reduceMotion)
                if isOpen {
                    UpdateIslandHeadline(model: model, presentation: presentation)
                        .transition(reveal(0))
                    if let calloutKind {
                        Button(calloutKind == .installed ? .updatesInstalledCalloutOpen : .updatesAwarenessOpen,
                               action: openCallout)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .transition(reveal(1))
                    }
                    UpdateIslandCloseButton(action: isPanel ? close : dismissCallout)
                        .transition(reveal(2))
                }
            }
            if showsBody, hasDetails {
                UpdateIslandDetails(presentation: presentation, awareness: awareness)
                    .transition(reveal(3))
            }
            if showsBody, !presentation.actions.isEmpty {
                UpdateIslandActions(presentation: presentation, action: action)
                    .transition(reveal(4))
            }
        }
        .controlSize(.large)
        .padding(isOpen ? Self.inset : Self.beadInset)
        .padding(.trailing, isOpen ? 2 : 0)
        // Nil lets the bead hug the mark. The island is centred in the canvas, so growing
        // from the bead carries the mark from the centre to the leading edge.
        .frame(width: isOpen ? (isPanel ? Self.panelWidth : Self.calloutWidth) : nil, alignment: .leading)
        .modifier(UpdateIslandGlass(reduceTransparency: reduceTransparency,
                                    glow: stage == .bead ? 1 : (stage == .open ? 0.45 : 0)))
        .scaleEffect(isAway && !reduceMotion ? 0.72 : 1, anchor: .top)
        .offset(y: isAway && !reduceMotion ? -34 : 0)
        .opacity(isAway ? 0 : 1)
        .padding(Self.canvasInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(presentation.phase == .failed && isPanel ? .orange : UpdateAwarenessMark.indigo)
        // The owner and the driver change these outside any transaction. Without these the
        // island would jump to its new size when a phase changes or the notes arrive.
        .animation(morph, value: model.content)
        .animation(morph, value: presentation.phase)
        .animation(morph, value: presentation.actions)
        .animation(morph, value: hasDetails)
        .animation(morph, value: presentation.notes?.count)
        .animation(morph, value: presentation.loadingNotes)
        .animation(morph, value: presentation.comic == nil)
        .onExitCommand(perform: isPanel ? close : dismissCallout)
        .environment(\.openURL, OpenURLAction { url in
            UpdateReleaseNotes.safeLink(url) == nil ? .discarded : .systemAction(url)
        })
        .task(id: model.isLeaving) {
            if model.isLeaving { await leave() } else { await arrive() }
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
        // A callout is small enough to land with a little life; the panel opens without bounce.
        withAnimation(isPanel ? morph : .spring(response: 0.5, dampingFraction: 0.86)) { stage = .open }
    }

    private func leave() async {
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.18)) { stage = .away }
            return
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 1)) { stage = .bead }
        try? await Task.sleep(for: .milliseconds(270))
        withAnimation(.easeIn(duration: 0.22)) { stage = .away }
    }
}

/// Replays arrival, the morph into the panel, and departure; previews have no panel owner.
private struct UpdateIslandPreviewStage: View {
    var kind = UpdateIslandAnnouncement.Kind.available
    var phase = UpdatePhase.available
    var startsAsPanel = false
    var reduceTransparency = false
    var reduceMotion = false
    @State private var model = UpdateIslandModel(content: .panel)
    @State private var presentation = UpdatePresentation(currentVersion: "0.5.0")

    var body: some View {
        VStack(spacing: 0) {
            UpdateIslandView(model: model, presentation: presentation, reduceTransparency: reduceTransparency,
                             reduceMotion: reduceMotion, openCallout: { model.content = .panel },
                             dismissCallout: { model.isLeaving = true }, close: { model.isLeaving = true })
            HStack {
                Button(model.isLeaving ? "Arrive" : "Leave") { model.isLeaving.toggle() }
                Button("Downloading") {
                    presentation.phase = .downloading
                    presentation.receivedBytes = 18_000_000
                    presentation.expectedBytes = 42_000_000
                }
                Button("Ready") { presentation.phase = .ready }
                Button("Up to date") { presentation.phase = .notFound }
            }
        }
        .padding(.bottom, 24)
        .frame(width: 680, height: 620)
        .background(LinearGradient(colors: [.teal.opacity(0.5), .indigo.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear {
            if !startsAsPanel { model.content = .callout(.init(kind: kind, version: "0.6.0")) }
            presentation.phase = phase
            presentation.offer = UpdateOffer(version: "0.6.0", stage: .notDownloaded, critical: false, major: false,
                                             informational: false, informationURL: nil, releaseNotesURL: nil)
            presentation.notes = [
                UpdateReleaseNoteBlock(id: 0, style: .heading(2), text: AttributedString("A quieter dock.")),
                UpdateReleaseNoteBlock(id: 1, text: AttributedString("Improved display placement across multiple monitors."), marker: "•"),
                UpdateReleaseNoteBlock(id: 2, text: AttributedString("More precise activation zones"), marker: "•")
            ]
        }
    }
}

#Preview("Callout into panel") {
    UpdateIslandPreviewStage()
}

#Preview("Ready callout, static") {
    UpdateIslandPreviewStage(kind: .ready, phase: .ready, reduceMotion: true)
}

#Preview("Panel, permission") {
    UpdateIslandPreviewStage(phase: .permission, startsAsPanel: true)
}

#Preview("Panel, error") {
    UpdateIslandPreviewStage(phase: .failed, startsAsPanel: true)
}

#Preview("Panel, German opaque") {
    UpdateIslandPreviewStage(startsAsPanel: true, reduceTransparency: true)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
