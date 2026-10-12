import SwiftUI

/// Three placeholder rows while Lookout's query encoder warms up and nothing has arrived yet (the mockup's `.skel`):
/// a 58 pt square and three bars per row, with a light band sweeping across each every 1.1 s. Under Reduce Motion the
/// placeholders stay still.
struct LookoutSkeleton: View {
    let reduceMotion: Bool

    /// Bar widths as shares of the text column, from the mockup.
    private static let bars: [CGFloat] = [0.46, 0.30, 0.78]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let phase = reduceMotion ? nil : Self.phase(at: context.date)
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    LookoutSkeletonRow(phase: phase, bars: Self.bars)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.lookoutSearching))
    }

    /// 0…1 through the 1.1 s sweep.
    private static func phase(at date: Date) -> CGFloat {
        let period = 1.1
        return CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
    }
}

/// One placeholder row: the square and the bars.
private struct LookoutSkeletonRow: View {
    /// Where the sweep is, or nil for still placeholders.
    let phase: CGFloat?
    let bars: [CGFloat]

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            LookoutPlaceholder(phase: phase, cornerRadius: 9)
                .frame(width: 58, height: 58)
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(bars, id: \.self) { share in
                        LookoutPlaceholder(phase: phase, cornerRadius: 5)
                            .frame(width: proxy.size.width * share, height: 10)
                    }
                }
                .padding(.top, 6)
            }
            .frame(height: 58)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

/// A rounded placeholder in the chip fill with the sweeping band.
private struct LookoutPlaceholder: View {
    let phase: CGFloat?
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = HubFilesTheme(scheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(theme.chip)
            .overlay {
                if let phase {
                    GeometryReader { proxy in
                        let band = max(proxy.size.width * 0.8, 40)
                        LinearGradient(colors: [.clear, theme.chipHighlight, .clear], startPoint: .leading,
                                       endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (proxy.size.width + band))
                    }
                }
            }
            .clipShape(shape)
    }
}

#Preview("Skeleton") {
    LookoutSkeleton(reduceMotion: false)
        .frame(width: 560)
        .padding()
        .background(.regularMaterial)
}

#Preview("Skeleton · Reduce Motion") {
    LookoutSkeleton(reduceMotion: true)
        .frame(width: 560)
        .padding()
        .background(.regularMaterial)
}
