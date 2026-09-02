import SwiftUI

/// Non-interactive illustration of where the dock rests on a display.
///
/// The scene is a scaled stand-in for a 1440×900 desktop, not a live view of the user's
/// arrangement: the reserved band stands for space macOS keeps for the system Dock, which is
/// what `usableDesktop` measures from. Offsets are clamped exactly like real placement, so
/// dragging past the edge parks the dock instead of moving it off-screen.
struct DockPlacementPreview: View {
    let reference: DockSettings.PositionReference
    let alignment: DockSettings.Alignment
    let horizontalOffset: Double
    let bottomDistance: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size = CGSize(width: 320, height: 200)
    /// Preview points per desktop point, for a 1440-point-wide reference display.
    private static let scale = Self.size.width / 1440
    private static let menuBarHeight: CGFloat = 6
    /// Stands for the space a bottom system Dock reserves.
    private static let reservedHeight: CGFloat = 14
    private static let dock = CGSize(width: 138, height: 18)
    private static let inset: CGFloat = 6

    /// Height above the display bottom that the chosen reference frame is measured from.
    private var referenceBottom: CGFloat {
        reference == .usableDesktop ? Self.reservedHeight : 0
    }

    private var dockOrigin: CGPoint {
        let anchorX: CGFloat = switch alignment {
        case .left: Self.inset + Self.dock.width / 2
        case .center: Self.size.width / 2
        case .right: Self.size.width - Self.inset - Self.dock.width / 2
        }
        let centerX = anchorX + CGFloat(horizontalOffset) * Self.scale
        let limit = Self.size.width - Self.inset - Self.dock.width / 2
        let clampedX = min(max(centerX, Self.inset + Self.dock.width / 2), limit)
        let bottom = referenceBottom + CGFloat(bottomDistance) * Self.scale
        let clampedBottom = min(bottom, Self.size.height - Self.menuBarHeight - Self.dock.height - Self.inset)
        return CGPoint(x: clampedX - Self.dock.width / 2,
                       y: Self.size.height - clampedBottom - Self.dock.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            menuBar
            reservedBand
            referenceLine
            dockPill.offset(x: dockOrigin.x, y: dockOrigin.y)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: dockOrigin)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: reference)
        .accessibilityHidden(true)
    }

    private var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.42),
                                Color(red: 0.35, green: 0.24, blue: 0.52),
                                Color(red: 0.19, green: 0.38, blue: 0.52)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var menuBar: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(height: Self.menuBarHeight)
    }

    private var reservedBand: some View {
        Rectangle()
            .fill(.black.opacity(0.14))
            .frame(height: Self.reservedHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Marks the edge the bottom distance is measured from.
    private var referenceLine: some View {
        Rectangle()
            .fill(.white.opacity(0.55))
            .frame(height: 1)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .offset(y: -referenceBottom)
            .mask(alignment: .bottom) {
                // Dashes read as a measurement guide rather than desktop content.
                HStack(spacing: 4) {
                    ForEach(0..<40, id: \.self) { _ in Rectangle().frame(width: 4) }
                }
                .frame(maxHeight: .infinity)
            }
    }

    private var dockPill: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill([Color.blue, .cyan, .pink, .orange, .gray, .indigo][index].gradient)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: Self.dock.width, height: Self.dock.height)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.3)))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

#if DEBUG
#Preview("Placement preview") {
    VStack(spacing: 16) {
        DockPlacementPreview(reference: .usableDesktop, alignment: .center,
                             horizontalOffset: 0, bottomDistance: 8)
        DockPlacementPreview(reference: .screenEdge, alignment: .right,
                             horizontalOffset: -120, bottomDistance: 120)
    }
    .padding()
}
#endif
