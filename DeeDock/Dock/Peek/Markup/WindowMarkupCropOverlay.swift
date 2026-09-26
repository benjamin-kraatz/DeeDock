import SwiftUI

/// The export selection drawn on the picture: a dim outside, an outline, and corner handles.
///
/// Works in document pixels through `scale`, like every gesture on the stage, so a crop moved by
/// hand and a crop typed in code land on the same pixels. Handles and moving are only live with
/// the crop tool; with any other tool the selection stays visible but inert.
struct WindowMarkupCropOverlay: View {
    let document: WindowMarkupDocument
    let scale: CGFloat
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin: CGRect?

    fileprivate enum Corner: CaseIterable {
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
        if let crop = document.crop {
            let frame = crop.applying(CGAffineTransform(scaleX: scale, y: scale))
            let size = CGSize(width: document.size.width * scale, height: document.size.height * scale)
            let editable = document.tool == .crop && !document.liveText
            ZStack(alignment: .topLeading) {
                dimming(frame: frame, size: size)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.95), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(tint, lineWidth: 3.5).opacity(editable ? 0.9 : 0.55))
                    .overlay { if editable { thirds } }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .contentShape(.rect)
                    .gesture(editable ? move : nil)
                    .pointerStyle(editable ? .grabIdle : .default)
                    // Inert with other tools, so drawing inside the selection reaches the canvas.
                    .allowsHitTesting(editable)
                if editable {
                    ForEach(Array(Corner.allCases.enumerated()), id: \.offset) { _, corner in
                        handle(corner, frame: frame)
                    }
                }
                measurement(crop)
                    .offset(x: frame.minX + 8, y: frame.maxY - 30)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(reduceMotion || origin != nil ? nil : .snappy(duration: 0.2), value: frame)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.markupCropAccessibility))
        }
    }

    /// Rule-of-thirds guides while the crop is being adjusted, like the system screenshot tool.
    private var thirds: some View {
        GeometryReader { geometry in
            Path { path in
                for step in 1...2 {
                    let x = geometry.size.width * CGFloat(step) / 3
                    let y = geometry.size.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private func measurement(_ crop: CGRect) -> some View {
        Text(verbatim: "\(Int(crop.width)) × \(Int(crop.height))")
            .font(.caption2.monospacedDigit().weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: .capsule)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
    }

    private func dimming(frame: CGRect, size: CGSize) -> some View {
        Rectangle()
            .fill(.black.opacity(0.5))
            .frame(width: size.width, height: size.height)
            .mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    private func handle(_ corner: Corner, frame: CGRect) -> some View {
        Circle()
            .fill(.white)
            .overlay { Circle().strokeBorder(tint, lineWidth: 3) }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 16, height: 16)
            .frame(width: frame.width + 16, height: frame.height + 16, alignment: corner.alignment)
            .offset(x: frame.minX - 8, y: frame.minY - 8)
            .gesture(resize(corner))
            .pointerStyle(.frameResize(position: corner.resizePosition))
            .accessibilityLabel(Text(.regionResize))
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = origin ?? document.crop ?? .zero
                origin = start
                let moved = start.offsetBy(dx: value.translation.width / scale, dy: value.translation.height / scale)
                let clamped = CGRect(x: min(max(moved.minX, 0), document.size.width - start.width),
                                     y: min(max(moved.minY, 0), document.size.height - start.height),
                                     width: start.width, height: start.height)
                document.crop = clamped.integral
            }
            .onEnded { _ in origin = nil }
    }

    private func resize(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = origin ?? document.crop ?? .zero
                origin = start
                let location = CGPoint(x: min(max(value.location.x / scale, 0), document.size.width),
                                       y: min(max(value.location.y / scale, 0), document.size.height))
                var (minX, minY, maxX, maxY) = (start.minX, start.minY, start.maxX, start.maxY)
                let minimum: CGFloat = 16
                switch corner {
                case .topLeading: minX = min(location.x, maxX - minimum); minY = min(location.y, maxY - minimum)
                case .topTrailing: maxX = max(location.x, minX + minimum); minY = min(location.y, maxY - minimum)
                case .bottomLeading: minX = min(location.x, maxX - minimum); maxY = max(location.y, minY + minimum)
                case .bottomTrailing: maxX = max(location.x, minX + minimum); maxY = max(location.y, minY + minimum)
                }
                document.crop = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
            }
            .onEnded { _ in origin = nil }
    }
}

private extension WindowMarkupCropOverlay.Corner {
    var resizePosition: FrameResizePosition {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}
