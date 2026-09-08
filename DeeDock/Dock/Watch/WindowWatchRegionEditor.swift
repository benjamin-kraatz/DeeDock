import SwiftUI

/// The live preview and the selection drawn on it.
///
/// The overlay and the cropping share top-left unit coordinates, so what the outline encloses is
/// what the watch samples. Letterbox margins never enter the selection: every gesture works in the
/// scaled image rectangle, not in the space the preview happens to occupy.
struct WindowWatchRegionEditor: View {
    let image: CGImage
    @Binding var region: WindowWatchRegion
    let editable: Bool
    let scanning: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin: CGRect?
    @State private var sweep = false

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Double(image.width), geometry.size.height / Double(image.height))
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            let unit = region.rect
            let frame = CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
                               width: unit.width * size.width, height: unit.height * size.height)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                dimming(frame: frame, size: size)
                selection(frame: frame, size: size)
                if editable {
                    ForEach(Array(Corner.allCases.enumerated()), id: \.offset) { _, corner in
                        handle(corner, frame: frame, size: size)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) { measurement(unit) }
            .clipShape(.rect(cornerRadius: 10))
            .contentShape(.rect)
            .gesture(draw(in: size))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: scanning, initial: true) { _, active in
            sweep = active && !reduceMotion
        }
        .accessibilityLabel(Text(.watchSelectedRegion))
    }

    /// The selection stated in the same percentages the sliders use, next to the outline it describes.
    private func measurement(_ unit: CGRect) -> some View {
        Text(verbatim: "\(percent(unit.width)) × \(percent(unit.height)) · \(percent(unit.minX)), \(percent(unit.minY))")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
            .padding(8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Everything outside the selection is pushed back so the watched area reads as the subject.
    private func dimming(frame: CGRect, size: CGSize) -> some View {
        Rectangle()
            .fill(.black.opacity(0.45))
            .frame(width: size.width, height: size.height)
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func selection(frame: CGRect, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(tint, lineWidth: 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.08)))
            .overlay { if scanning { scan(frame: frame) } }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .contentShape(.rect)
            .gesture(move(in: size))
            .animation(.snappy(duration: 0.18), value: frame)
    }

    /// A sweep over the watched area while samples are being taken, so a running watch is legible
    /// at a glance. It reports activity, never progress: nothing here knows when the watch ends.
    private func scan(frame: CGRect) -> some View {
        LinearGradient(colors: [.clear, tint.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 46)
            .offset(y: sweep ? frame.height : -46)
            .animation(sweep ? .linear(duration: 2.4).repeatForever(autoreverses: false) : nil, value: sweep)
            .frame(height: frame.height, alignment: .top)
            .clipShape(.rect(cornerRadius: 6))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func handle(_ corner: Corner, frame: CGRect, size: CGSize) -> some View {
        Circle()
            .fill(.white)
            .overlay { Circle().strokeBorder(tint, lineWidth: 3) }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 15, height: 15)
            .frame(width: frame.width, height: frame.height, alignment: corner.alignment)
            .offset(x: frame.minX, y: frame.minY)
            .gesture(resize(corner, in: size))
            .accessibilityLabel(Text(.watchRegionResize))
    }

    private func draw(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            guard editable else { return }
            let start = point(value.startLocation, in: size)
            let end = point(value.location, in: size)
            apply(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y)))
        }
    }

    /// Moving keeps the selection's size; the drag is clamped so it cannot walk off the window.
    private func move(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard editable else { return }
                let start = origin ?? region.rect
                origin = start
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                apply(CGRect(x: min(max(start.minX + dx, 0), 1 - start.width),
                             y: min(max(start.minY + dy, 0), 1 - start.height),
                             width: start.width, height: start.height))
            }
            .onEnded { _ in origin = nil }
    }

    private func resize(_ corner: Corner, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard editable else { return }
                let start = origin ?? region.rect
                origin = start
                let location = point(value.location, in: size)
                var (minX, minY, maxX, maxY) = (start.minX, start.minY, start.maxX, start.maxY)
                switch corner {
                case .topLeading:
                    minX = min(location.x, maxX - 0.05); minY = min(location.y, maxY - 0.05)
                case .topTrailing:
                    maxX = max(location.x, minX + 0.05); minY = min(location.y, maxY - 0.05)
                case .bottomLeading:
                    minX = min(location.x, maxX - 0.05); maxY = max(location.y, minY + 0.05)
                case .bottomTrailing:
                    maxX = max(location.x, minX + 0.05); maxY = max(location.y, minY + 0.05)
                }
                apply(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
            .onEnded { _ in origin = nil }
    }

    private func point(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(location.x / size.width, 0), 1), y: min(max(location.y / size.height, 0), 1))
    }

    private func apply(_ rect: CGRect) {
        region = WindowWatchRegion(x: rect.minX, y: rect.minY,
                                   width: rect.width, height: rect.height).clamped
    }
}
