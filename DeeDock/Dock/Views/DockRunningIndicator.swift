import SwiftUI

/// A running-state marker shared by live icons and inert Settings samples.
/// Hidden markers retain the reserved strip so appearance changes cannot shift icons or hit regions.
///
/// An app running in background draws the same marker muted, like the system Dock's gray dot.
/// Running and background are two stacked layers that crossfade, so the change never moves the
/// marker; under Reduce Motion it switches at once.
struct DockRunningIndicator: View {
    let style: DockSettings.RunningIndicatorStyle
    let edge: DockEdge
    /// Callers draw the marker only while the app runs; `.notRunning` leaves the strip empty.
    var state: DockRunningState = .running
    /// Inside an island the marker takes the island's tint and a soft matching glow.
    @Environment(\.dockIslandTint) private var islandTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The crossfade between the running and background markers, shared with the overlay styles.
    /// A touch longer than the dock's 0.15–0.18 s layout eases: the marker does not move, so the
    /// colour change is all there is to see, and a symmetric curve keeps the two layers level.
    static let stateAnimation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        ZStack {
            marker
                .foregroundStyle(islandTint ?? .primary.opacity(0.8))
                .shadow(color: islandTint?.opacity(0.9) ?? .clear, radius: islandTint == nil ? 0 : 3)
                .opacity(state == .running ? 1 : 0)
            marker
                .foregroundStyle(mutedStyle)
                .opacity(state == .background ? 1 : 0)
        }
        .animation(reduceMotion ? nil : Self.stateAnimation, value: state)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// The system Dock's background dot measures as white at roughly a quarter alpha over the
    /// glass, about a third of its running dot. `.tertiary` lands there against this marker's
    /// `.primary.opacity(0.8)` in both appearances and follows Increase Contrast; `.secondary`
    /// is barely dimmer than running. Inside an island the tint stays at half strength, without
    /// the glow, so the marker still belongs to its island.
    private var mutedStyle: AnyShapeStyle {
        islandTint.map { AnyShapeStyle($0.opacity(0.45)) } ?? AnyShapeStyle(.tertiary)
    }

    @ViewBuilder private var marker: some View {
        switch style {
        case .dot:
            Circle().frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
        case .bar:
            Capsule().frame(width: edge.isVertical ? DockGeometry.indicatorSize : 16,
                            height: edge.isVertical ? 16 : DockGeometry.indicatorSize)
        case .square:
            Rectangle().frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
        case .targetLock, .orbit, .stardust, .powerBadge, .hidden:
            Color.clear.frame(width: DockGeometry.indicatorSize, height: DockGeometry.indicatorSize)
        }
    }
}

#if DEBUG
/// Running and background markers side by side for every style, in light or dark appearance.
private struct DockRunningIndicatorGallery: View {
    let scheme: ColorScheme
    var tint: Color? = nil

    var body: some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(DockSettings.RunningIndicatorStyle.allCases, id: \.self) { style in
                GridRow {
                    Text(verbatim: style.rawValue).font(.caption).gridColumnAlignment(.leading)
                    ForEach([DockRunningState.running, .background], id: \.self) { state in
                        DockIconPresentation(icon: NSImage(systemSymbolName: "paperplane.fill",
                                                           accessibilityDescription: nil)!,
                                             size: 44, edge: .bottom, available: true, running: state,
                                             launching: false, keyboardSelected: false,
                                             runningIndicatorStyle: style,
                                             indicatorVariant: DockIndicatorVariant(identity: style.rawValue))
                    }
                }
            }
        }
        .padding(20)
        .environment(\.dockIslandTint, tint)
        .background(.regularMaterial)
        .preferredColorScheme(scheme)
    }
}

#Preview("Running vs background, light") { DockRunningIndicatorGallery(scheme: .light) }
#Preview("Running vs background, dark") { DockRunningIndicatorGallery(scheme: .dark) }
#Preview("Running vs background, island tint") { DockRunningIndicatorGallery(scheme: .dark, tint: .teal) }

/// Toggle between running and background to watch the crossfade; the markers never move.
#Preview("Running to background crossfade") {
    @Previewable @State var background = false
    VStack(spacing: 20) {
        HStack(spacing: 28) {
            ForEach([DockSettings.RunningIndicatorStyle.dot, .bar, .square], id: \.self) { style in
                DockRunningIndicator(style: style, edge: .bottom, state: background ? .background : .running)
            }
            DockRunningIndicator(style: .dot, edge: .bottom, state: background ? .background : .running)
                .environment(\.dockIslandTint, .teal)
        }
        .scaleEffect(3)
        .frame(width: 240, height: 48)
        Toggle(isOn: $background) { Text(.appStatusRunningInBackground) }
    }
    .padding(24)
    .background(.regularMaterial)
}
#endif
