import SwiftUI

/// The volume's icon, name, and capacity, as the card shows them in every phase.
struct VolumeCardHeader: View {
    let volume: VolumeDockItem
    let reduceMotion: Bool
    /// Dims the artwork while an eject is under way, matching the tile in the dock.
    let dimmed: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: volume.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
                .opacity(dimmed ? 0.45 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: dimmed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: volume.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(capacityText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let fraction = VolumeCapacityFormat.usedFraction(total: volume.info.totalCapacity,
                                                                    available: volume.info.availableCapacity) {
                    VolumeCapacityBar(fraction: fraction, reduceMotion: reduceMotion)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var capacityText: LocalizedStringResource {
        guard let total = volume.info.totalCapacity else { return .volumeCapacityUnknown }
        guard let available = volume.info.availableCapacity else {
            return .volumeCapacityTotal(total: VolumeCapacityFormat.string(total))
        }
        return .volumeCapacitySummary(total: VolumeCapacityFormat.string(total),
                                      available: VolumeCapacityFormat.string(available))
    }
}

/// Used space as a filled track. It grows in from empty when the card opens.
struct VolumeCapacityBar: View {
    let fraction: Double
    let reduceMotion: Bool
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fillStyle)
                    .frame(width: max(proxy.size.height, proxy.size.width * (shown ? fraction : 0)))
            }
        }
        .frame(height: 6)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.15).delay(0.08)) { shown = true }
        }
        .accessibilityHidden(true)
    }

    /// Nearly full volumes turn orange, then red, the way storage warnings read elsewhere in macOS.
    private var fillStyle: AnyShapeStyle {
        switch fraction {
        case 0.95...: AnyShapeStyle(Color.red.gradient)
        case 0.85...: AnyShapeStyle(Color.orange.gradient)
        default: AnyShapeStyle(Color.accentColor.gradient)
        }
    }
}
