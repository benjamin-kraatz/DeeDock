import SwiftUI

/// The macOS Dock giving its band of desktop back.
///
/// This one diagram is drawn rather than reused: it depicts the *system* Dock, so borrowing
/// `DockDisplayDiagram` — which renders DeeDock's own placement — would say the wrong thing.
/// It follows the live measurement: while space is still reserved it demonstrates the change,
/// and once the space is released it holds the settled state.
struct OnboardingSystemDockStage: View {
    /// Whether the macOS Dock is currently holding desktop space on any screen.
    let reservesSpace: Bool
    /// Previews and the surrounding tour can pass an explicit value; the stage otherwise
    /// follows the system setting, matching `DockSampleView`.
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    /// 0 with the Dock resting in place, 1 with it withdrawn and the desktop reclaimed.
    @State private var withdrawal: Double = 0

    private static let screen = CGSize(width: 306, height: 192)
    private static let menuBarHeight: CGFloat = 12
    private static let dockHeight: CGFloat = 26

    private var progress: Double { reservesSpace ? withdrawal : 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.indigo.gradient)
                .overlay(alignment: .top) {
                    Rectangle().fill(.black.opacity(0.18)).frame(height: Self.menuBarHeight)
                }
                .overlay(alignment: .bottom) { reclaimedBand }
            systemDock
        }
        .frame(width: Self.screen.width, height: Self.screen.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: loopIdentity) { await demonstrate() }
    }

    /// Restarting the loop when either input changes keeps a single task in flight.
    private var loopIdentity: String { "\(reduceMotion)-\(reservesSpace)" }

    /// The strip of desktop the Dock hands back, shown filling in as it withdraws.
    private var reclaimedBand: some View {
        Rectangle()
            .fill(.white.opacity(0.14 * progress))
            .frame(height: Self.dockHeight)
    }

    private var systemDock: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill([Color.blue, .cyan, .pink, .orange, .mint, .gray][index].opacity(0.95))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                }
        }
        .padding(.bottom, 5)
        // Sliding fully past the screen edge, then fading, matches what macOS does when the
        // Dock is set to hide: the space is released only once it has left.
        .offset(y: (Self.dockHeight + 12) * progress)
        .opacity(1 - progress)
    }

    private func demonstrate() async {
        guard reservesSpace, !reduceMotion else {
            withdrawal = reservesSpace ? 0 : 1
            return
        }
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.65)) { withdrawal = 0 }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.65)) { withdrawal = 1 }
            try? await Task.sleep(for: .seconds(1.9))
            guard !Task.isCancelled else { return }
        }
    }
}

#if DEBUG
#Preview("System Dock stage — still reserving") {
    OnboardingStage(tint: OnboardingStep.systemDock.tint) {
        OnboardingSystemDockStage(reservesSpace: true)
    }
    .padding(28).frame(width: 700)
}

#Preview("System Dock stage — released") {
    OnboardingStage(tint: OnboardingStep.systemDock.tint) {
        OnboardingSystemDockStage(reservesSpace: false)
    }
    .padding(28).frame(width: 700)
}
#endif
