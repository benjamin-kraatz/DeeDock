import SwiftUI

/// Sizes for the folder icons inside the orb: bigger folders get bigger icons on a log scale,
/// and every icon shrinks together when the pile would overflow the sphere.
nonisolated enum VaporPileSizing {
    /// An icon's edge length before fitting, 20…40 pt, from the folder's allocated size.
    static func baseSize(bytes: Int64) -> CGFloat {
        guard bytes > 0 else { return 24 }
        let megabytes = max(Double(bytes) / 1_000_000, 1)
        return CGFloat(min(max(20 + 6 * log10(megabytes), 20), 40))
    }

    /// The factor that makes all icons fit in about half the sphere's area.
    static func fitScale(sizes: [CGFloat], diameter: CGFloat) -> CGFloat {
        let area = sizes.reduce(0) { $0 + $1 * $1 }
        let available = .pi * pow(diameter / 2 - 6, 2) * 0.5
        guard area > available, area > 0 else { return 1 }
        return sqrt(available / area)
    }
}

/// Phase 1's settled pile: icons stacked in rows from the bottom of the sphere. Phase 2 swaps
/// this for 2D physics; ``VaporPileSizing`` stays the size source.
struct VaporOrbPile: View {
    let folders: [VaporFolder]
    let diameter: CGFloat

    var body: some View {
        let sizes = folders.map { VaporPileSizing.baseSize(bytes: $0.measurement.bytes) }
        let scale = VaporPileSizing.fitScale(sizes: sizes, diameter: diameter)
        let perRow = max(Int((diameter * 0.8) / ((sizes.max() ?? 24) * scale)), 1)
        let rows = stride(from: 0, to: folders.count, by: perRow).map { Array(folders.indices[$0..<min($0 + perRow, folders.count)]) }
        VStack(spacing: -4) {
            Spacer(minLength: 0)
            ForEach(rows.reversed(), id: \.first) { row in
                HStack(spacing: -2) {
                    ForEach(row, id: \.self) { index in
                        VaporFolderIcon(size: sizes[index] * scale)
                            .rotationEffect(.degrees(Double((index * 37) % 24) - 12))
                    }
                }
            }
        }
        .padding(.bottom, diameter * 0.12)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
