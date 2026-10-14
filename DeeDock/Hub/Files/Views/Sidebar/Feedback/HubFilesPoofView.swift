import SwiftUI

/// The Dock's "poof" when a row is dragged out of the sidebar: eight soft puffs that burst
/// outward, grow, and fade in six tenths of a second.
///
/// AppKit's own poof (`NSShowAnimationEffect`) has been deprecated since macOS 14, so the puffs
/// are drawn here, in an overlay window at the release point. Geometry follows the mockup's
/// `puff` keyframes; the spread is fixed per puff rather than random so every poof looks the same.
struct HubFilesPoofView: View {
    /// How long the last puff takes to fade: the burst plus the final puff's delay.
    static let duration: Double = 0.6 + 7 * 0.012

    /// One puff's direction, how far it travels, and when it starts.
    private struct Puff: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let delay: Double

        init(index: Int) {
            id = index
            angle = Double(index) / 8 * 2 * Double.pi + 0.3
            distance = 16 + CGFloat((index * 7) % 10)
            delay = Double(index) * 0.012
        }
    }

    private static let puffs: [Puff] = (0..<8).map(Puff.init(index:))

    @State private var burst = false

    var body: some View {
        ZStack {
            ForEach(Self.puffs) { puff in
                Circle()
                    .fill(RadialGradient(
                        stops: [.init(color: .white, location: 0),
                                .init(color: Color(red: 0.875, green: 0.882, blue: 0.91), location: 0.55),
                                .init(color: Color(red: 0.725, green: 0.737, blue: 0.784), location: 1)],
                        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 12))
                    .frame(width: 24, height: 24)
                    .scaleEffect(burst ? 1.6 : 0.35)
                    .offset(x: burst ? cos(puff.angle) * puff.distance : 0,
                            y: burst ? sin(puff.angle) * puff.distance : 0)
                    .opacity(burst ? 0 : 0.95)
                    .animation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.6).delay(puff.delay), value: burst)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { burst = true }
        .accessibilityHidden(true)
    }
}

#Preview("Poof") {
    HubFilesPoofView()
        .frame(width: HubFilesSidebarMetrics.poofSize, height: HubFilesSidebarMetrics.poofSize)
        .background(Color(red: 0.08, green: 0.09, blue: 0.14))
}

#Preview("Poof · light") {
    HubFilesPoofView()
        .frame(width: HubFilesSidebarMetrics.poofSize, height: HubFilesSidebarMetrics.poofSize)
        .background(Color(red: 0.93, green: 0.94, blue: 0.97))
}
