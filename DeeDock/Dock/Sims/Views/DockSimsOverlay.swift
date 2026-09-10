import SwiftUI

/// Decorative mood mark drawn over one pinned application's artwork.
///
/// The mark is the only thing that moves: the app icon keeps its own position, scale, and
/// launch motion, so Sims never competes with magnification or the running indicator. Mood
/// is recomputed from ``DockSimsPinState`` and the timeline clock rather than read from the
/// store, so hunger and loneliness drift without any write or observation churn.
///
/// The view is purely decorative. It takes no hits and is hidden from VoiceOver; the mood is
/// announced on the pin itself through the button's accessibility value.
struct DockSimsOverlay: View {
    /// Care clocks and normalized (0…1) animation strength for this pin.
    let state: DockSimsPinState
    /// Current magnified icon dimension in logical points, matching `DockIconPresentation`.
    let size: CGFloat
    /// Screen edge the dock sits on; decides which side carries the indicator strip.
    let edge: DockEdge
    /// Idle-fade opacity applied to the icons, so the mark dims with the artwork.
    var artworkOpacity: Double = 1
    /// False for a hidden, fully faded, or Reduce Motion dock: the mark is drawn at rest.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One full loop of the idle motion. Elapsed time wraps here so the phase never jumps.
    private static let period: Double = 4
    private var markSize: CGFloat { max(9, size * 0.30) }
    private var inset: CGFloat { max(1, size * 0.04) }
    private var isMoving: Bool { animated && !reduceMotion }

    var body: some View {
        Group {
            if isMoving {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                    mark(at: context.date, phase: Self.phase(at: context.date))
                }
            } else {
                mark(at: .now, phase: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0…1 position within one loop, derived from absolute time so every pin shares a clock
    /// and no state has to survive a view rebuild.
    private static func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    private func mark(at now: Date, phase: Double) -> some View {
        let mood = state.mood(at: now)
        let motion = Motion(idle: mood.idle, phase: phase,
                            intensity: isMoving ? min(max(state.intensity, 0), 1) : 0,
                            markSize: markSize)
        return Image(systemName: mood.symbolName)
            .font(.system(size: markSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Self.tint(mood))
            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
            .accessibilityLabel(Text(mood.title))
            .scaleEffect(motion.scale)
            .rotationEffect(.degrees(motion.rotation))
            .offset(x: motion.offset.width, y: motion.offset.height)
            .opacity(artworkOpacity)
            // The presentation's frame includes the indicator strip; padding keeps the mark on
            // the artwork for every edge, the way the badge's hit target does for top/right.
            .padding(.bottom, edge == .bottom ? DockGeometry.indicatorAreaDepth : 0)
            .padding(.leading, edge == .left ? DockGeometry.indicatorAreaDepth : 0)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private static func tint(_ mood: DockSimsMood) -> Color {
        switch mood {
        case .playful: .yellow
        case .content: .pink
        case .hungry: .green
        case .lonely: .cyan
        }
    }

    /// Amplitude comes from the user's intensity slider; the shape comes from the mood.
    private struct Motion {
        var scale: Double = 1
        var rotation: Double = 0
        var offset: CGSize = .zero

        init(idle: DockSimsIdle, phase: Double, intensity: Double, markSize: CGFloat) {
            guard intensity > 0 else { return }
            let turn = phase * 2 * .pi
            switch idle {
            case .bounce:
                // Two hops per loop with a rest between them, absolute-valued so the mark
                // never sinks below its resting line.
                let hop = abs(sin(turn * 2))
                offset = CGSize(width: 0, height: -Double(markSize) * 0.35 * intensity * hop)
                scale = 1 + 0.06 * intensity * hop
            case .breathe:
                scale = 1 + 0.14 * intensity * (0.5 + 0.5 * sin(turn))
            case .sway:
                rotation = 10 * intensity * sin(turn)
                offset = CGSize(width: Double(markSize) * 0.16 * intensity * sin(turn), height: 0)
            }
        }
    }
}

#if DEBUG
private enum DockSimsOverlayPreview {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func state(fedHoursAgo: Double, cheeredHoursAgo: Double, intensity: Double) -> DockSimsPinState {
        DockSimsPinState(pinID: "safari",
                         lastFedAt: now.addingTimeInterval(-fedHoursAgo * 3_600),
                         lastCheeredAt: now.addingTimeInterval(-cheeredHoursAgo * 3_600),
                         intensity: intensity)
    }

    static let playful = state(fedHoursAgo: 0, cheeredHoursAgo: 0, intensity: 0.55)
    static let content = state(fedHoursAgo: 3, cheeredHoursAgo: 4, intensity: 0.55)
    static let hungry = state(fedHoursAgo: 7, cheeredHoursAgo: 0, intensity: 0.55)
    static let lonely = state(fedHoursAgo: 0.2, cheeredHoursAgo: 9, intensity: 0.55)

    @ViewBuilder
    static func tile(_ state: DockSimsPinState, animated: Bool, size: CGFloat = 64) -> some View {
        DockIconPresentation(size: size, edge: .bottom, available: true, running: true,
                             launching: false, keyboardSelected: false) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.indigo.gradient)
        }
        .overlay {
            DockSimsOverlay(state: state, size: size, edge: .bottom, animated: animated)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Moods, animated") {
    HStack(spacing: 16) {
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.playful, animated: true)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.content, animated: true)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.hungry, animated: true)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.lonely, animated: true)
    }
    .padding(24)
    .background(.black)
}

#Preview("Reduce Motion, at rest") {
    HStack(spacing: 16) {
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.playful, animated: false)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.content, animated: false)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.hungry, animated: false)
        DockSimsOverlayPreview.tile(DockSimsOverlayPreview.lonely, animated: false)
    }
    .padding(24)
    .background(.black)
    .environment(\.accessibilityReduceMotion, true)
}

#Preview("Low and high intensity") {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            DockSimsOverlayPreview.tile(
                DockSimsOverlayPreview.state(fedHoursAgo: 0, cheeredHoursAgo: 0, intensity: 0.15),
                animated: true)
            DockSimsOverlayPreview.tile(
                DockSimsOverlayPreview.state(fedHoursAgo: 7, cheeredHoursAgo: 0, intensity: 0.15),
                animated: true)
        }
        HStack(spacing: 16) {
            DockSimsOverlayPreview.tile(
                DockSimsOverlayPreview.state(fedHoursAgo: 0, cheeredHoursAgo: 0, intensity: 1),
                animated: true)
            DockSimsOverlayPreview.tile(
                DockSimsOverlayPreview.state(fedHoursAgo: 7, cheeredHoursAgo: 0, intensity: 1),
                animated: true)
        }
    }
    .padding(24)
    .background(.black)
}

#Preview("Every edge") {
    HStack(spacing: 16) {
        ForEach(DockEdge.allCases, id: \.self) { edge in
            DockIconPresentation(size: 64, edge: edge, available: true, running: true,
                                 launching: false, keyboardSelected: false) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.indigo.gradient)
            }
            .overlay {
                DockSimsOverlay(state: DockSimsOverlayPreview.playful, size: 64, edge: edge)
                    .accessibilityHidden(true)
            }
        }
    }
    .padding(24)
    .background(.black)
}
#endif
