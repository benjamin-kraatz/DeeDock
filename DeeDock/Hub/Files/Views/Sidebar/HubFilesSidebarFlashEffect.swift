import SwiftUI

/// Plays a row's one-shot highlight: the arrival glow (an accent fill that fades while a soft
/// light sweeps across) or the pulse for a folder that was already there, which also lifts the
/// row to 103 % at its peak.
///
/// A new flash token replays from the start without rebuilding the row, so hover and the
/// current-location fill keep their identity. Under Reduce Motion the fill still fades, which
/// is a color change rather than motion, but nothing sweeps or scales.
struct HubFilesSidebarFlashEffect: ViewModifier {
    let flash: HubFilesSidebarModel.Flash?

    /// The flash being drawn; kept after the model forgets it so the tail of the fade completes.
    @State private var playing: HubFilesSidebarModel.Flash?
    /// 0 at the start of a flash, 1 when it has fully faded.
    @State private var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .modifier(HubFilesSidebarFlashPose(kind: playing?.kind ?? .arrival, progress: progress))
            .onChange(of: flash?.token, initial: true) { _, token in
                guard let flash, token != nil else { return }
                var restart = Transaction()
                restart.disablesAnimations = true
                withTransaction(restart) {
                    playing = flash
                    progress = 0
                }
                withAnimation(.linear(duration: flash.kind == .arrival ? 1.6 : 0.7)) { progress = 1 }
            }
    }
}

/// One frame of a flash. Animatable through `progress`, so the piecewise fade, the sweep, and
/// the pulse's scale are evaluated on every frame rather than interpolated end to end.
private struct HubFilesSidebarFlashPose: ViewModifier, Animatable {
    let kind: HubFilesSidebarModel.Flash.Kind
    var progress: CGFloat

    @Environment(\.colorScheme) private var scheme

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if progress < 1 {
                    HubFilesSidebarFlashFrame(kind: kind, progress: progress, scheme: scheme)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // After the overlay, so the fill and line lift with the row.
            .scaleEffect(kind == .pulse && !HubFilesMotion.reduceMotion ? pulseScale : 1)
    }

    /// The pulse rises to 103 % in its first quarter and settles back over the rest.
    private var pulseScale: CGFloat {
        1 + 0.03 * (progress < 0.25 ? progress / 0.25 : 1 - (progress - 0.25) / 0.75)
    }
}

/// The accent fill, its inner line, and (for arrivals) the sweep at one `progress`.
private struct HubFilesSidebarFlashFrame: View {
    let kind: HubFilesSidebarModel.Flash.Kind
    let progress: CGFloat
    let scheme: ColorScheme

    var body: some View {
        let theme = HubFilesTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: HubStyle.rowRadius, style: .continuous)
        ZStack {
            shape.fill(theme.accentSelection)
            shape.strokeBorder(theme.accentLine, lineWidth: 1)
        }
        .opacity(fillOpacity)
        .overlay {
            if kind == .arrival, !HubFilesMotion.reduceMotion {
                HubFilesSidebarSweep(progress: sweepProgress, scheme: scheme)
                    .clipShape(shape)
            }
        }
    }

    /// Arrival holds full strength through the first fifth of an eased 1.6 s, then fades, as the
    /// mockup's `fresh` keyframes do under `ease-out`. The pulse peaks at a quarter and fades.
    private var fillOpacity: Double {
        switch kind {
        case .arrival:
            let eased = Self.easeOut(progress)
            return eased < 0.18 ? 1 : Double(1 - (eased - 0.18) / 0.82)
        case .pulse:
            return progress < 0.25 ? Double(progress / 0.25) : Double(1 - (progress - 0.25) / 0.75)
        }
    }

    /// The sweep starts 0.12 s in and crosses in 0.9 s, easing out (`sweep .9s .12s ease-out`).
    private var sweepProgress: CGFloat {
        Self.easeOut(min(max((progress * 1.6 - 0.12) / 0.9, 0), 1))
    }

    private static func easeOut(_ t: CGFloat) -> CGFloat {
        1 - (1 - t) * (1 - t)
    }
}

/// A diagonal band of light that crosses the row once as `progress` goes from 0 to 1.
///
/// Sized from the mockup's `sweep`: a soft band about three quarters of the row wide, entering
/// from well past the left edge and leaving well past the right, tilted 10°.
private struct HubFilesSidebarSweep: View {
    var progress: CGFloat
    let scheme: ColorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bandWidth = width * 0.78
            // The band's center travels from -0.62 to 1.78 row widths.
            let center = -0.62 * width + progress * 2.4 * width
            LinearGradient(colors: [.clear, .white.opacity(scheme == .dark ? 0.22 : 0.7), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: bandWidth, height: proxy.size.height * 2)
                .rotationEffect(.degrees(10))
                .position(x: center, y: proxy.size.height / 2)
        }
    }
}

/// A row stand-in for inspecting the flash at fixed moments.
private struct HubFilesSidebarFlashSample: View {
    let kind: HubFilesSidebarModel.Flash.Kind
    let progress: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 19, height: 19)
            Text(verbatim: "DeeDock")
                .font(.system(size: 13.5))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: HubFilesSidebarMetrics.rowWidth, height: HubFilesMetrics.rowHeight)
        .modifier(HubFilesSidebarFlashPose(kind: kind, progress: progress))
    }
}

#Preview("Flash frames") {
    VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: "Arrival: hold, sweep, fade")
            .font(.caption)
            .foregroundStyle(.secondary)
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.05)
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.2)
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.35)
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.7)
        Text(verbatim: "Pulse: peak")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        HubFilesSidebarFlashSample(kind: .pulse, progress: 0.25)
    }
    .padding(20)
}

#Preview("Flash frames · light") {
    VStack(alignment: .leading, spacing: 6) {
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.2)
        HubFilesSidebarFlashSample(kind: .arrival, progress: 0.35)
        HubFilesSidebarFlashSample(kind: .pulse, progress: 0.25)
    }
    .padding(20)
    .preferredColorScheme(.light)
}
