import SwiftUI

/// Owns only visual timing. SwiftUI cancels its sleep when a tile disappears or its inputs change.
/// The artwork moves independently of layout, focus rings, running markers, and hit regions.
struct DockLaunchMotion: ViewModifier {
    let style: DockLaunchAnimation
    let request: Date?
    let busy: Bool
    let enabled: Bool
    let edge: DockEdge
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    private struct Playback: Equatable {
        let request: Date?
        let style: DockLaunchAnimation
        let allowed: Bool
        let busy: Bool
    }

    func body(content: Content) -> some View {
        let playback = Playback(request: request, style: style,
                                allowed: enabled && !reduceMotion && style != .none, busy: busy)
        // Keep the artwork's identity stable as playback starts and stops. Pausing the
        // schedule also prevents idle icons from requesting animation frames.
        TimelineView(.animation(paused: !active || !playback.allowed)) { context in
            let elapsed = request.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let progress = elapsed.truncatingRemainder(dividingBy: style.duration) / style.duration
            let pose = active && playback.allowed && request != nil
                ? style.pose(at: progress, size: size) : DockLaunchAnimation.Pose()
            content
                .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                .rotationEffect(.degrees(pose.rotation))
                .rotation3DEffect(.degrees(pose.flip), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                .offset(x: inwardOffset(pose.lift).width, y: inwardOffset(pose.lift).height)
        }
        .task(id: playback) {
            guard playback.allowed, let request else { active = false; return }
            let elapsed = max(0, Date().timeIntervalSince(request))
            // New views never replay an old completed launch. An active view finishes its current
            // cycle when Workspace completes, including requests that finish in under one frame.
            guard elapsed < 30, busy || active || elapsed < style.duration else { active = false; return }
            active = true
            let end = busy ? 30 : max(style.duration, ceil(elapsed / style.duration) * style.duration)
            do {
                try await Task.sleep(for: .seconds(max(0, end - elapsed)))
            } catch { return }
            active = false
        }
    }

    private func inwardOffset(_ distance: CGFloat) -> CGSize {
        switch edge {
        case .bottom: CGSize(width: 0, height: -distance)
        case .top: CGSize(width: 0, height: distance)
        case .left: CGSize(width: distance, height: 0)
        case .right: CGSize(width: -distance, height: 0)
        }
    }
}
