import SwiftUI

/// The welcome step's drawn example thumbnails, from the approved mockup's 60-unit SVGs (`TH.beach`, `TH.shot`,
/// `TH.pdf`): a dog on a beach, a checkout screenshot with an error, and a page with a highlighted passage. They are
/// illustrations, never the person's files.
///
/// The photo fills its tile (the SVG's `slice`); the screenshot and the page sit in a centered square (the SVG's
/// default `meet`), as the mockup draws them.
struct LookoutSampleThumbnail: View {
    enum Sample {
        case beach, screenshot, page
    }

    let sample: Sample

    var body: some View {
        Canvas { context, size in
            let fills = sample == .beach
            let scale = fills ? max(size.width, size.height) / 60 : min(size.width, size.height) / 60
            let origin = CGPoint(x: (size.width - 60 * scale) / 2, y: (size.height - 60 * scale) / 2)
            let drawing = LookoutSampleDrawing(context: context, origin: origin, scale: scale)
            switch sample {
            case .beach: drawing.beach()
            case .screenshot: drawing.screenshot()
            case .page: drawing.page()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Draws one sample in the SVGs' 60 × 60 space, mapped into the canvas.
private struct LookoutSampleDrawing {
    let context: GraphicsContext
    let origin: CGPoint
    let scale: CGFloat

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
    }

    private func fill(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color,
                      radius: CGFloat = 0) {
        let shape = Path(roundedRect: rect(x, y, width, height), cornerRadius: radius * scale)
        context.fill(shape, with: .color(color))
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: rect(x - radius, y - radius, radius * 2, radius * 2)), with: .color(color))
    }

    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255).opacity(opacity)
    }

    // MARK: Samples

    /// `TH.beach`: sky, sun, sea, sand and a brown dog.
    func beach() {
        let sky = Gradient(colors: [Self.hex(0x7EC8FF), Self.hex(0xCDEAFF)])
        context.fill(Path(rect(0, 0, 60, 60)), with: .linearGradient(sky, startPoint: point(0, 0), endPoint: point(0, 60)))
        circle(46, 13, 6, Self.hex(0xFFF6C4))
        var sea = Path()
        sea.move(to: point(0, 33))
        sea.addQuadCurve(to: point(30, 33), control: point(15, 30))
        sea.addQuadCurve(to: point(60, 32), control: point(45, 36))
        sea.addLine(to: point(60, 40))
        sea.addLine(to: point(0, 40))
        sea.closeSubpath()
        context.fill(sea, with: .color(Self.hex(0x3D8FD1)))
        var sand = Path()
        sand.move(to: point(0, 38))
        sand.addQuadCurve(to: point(60, 38), control: point(20, 35))
        sand.addLine(to: point(60, 60))
        sand.addLine(to: point(0, 60))
        sand.closeSubpath()
        context.fill(sand, with: .color(Self.hex(0xECD29A)))
        let dog = Self.hex(0x6B4423)
        context.fill(Path(ellipseIn: rect(19, 40.4, 16, 7.2)), with: .color(dog))
        circle(35, 40.5, 3, dog)
        var ear = Path()
        ear.move(to: point(36.5, 38.2))
        ear.addLine(to: point(39, 37))
        ear.addLine(to: point(38.4, 40))
        ear.closeSubpath()
        context.fill(ear, with: .color(dog))
        for (x, y) in [(21.0, 45.5), (25.0, 46.0), (29.0, 46.0), (32.5, 45.5)] {
            fill(x, y, 1.8, 5, dog, radius: 0.8)
        }
        var tail = Path()
        tail.move(to: point(19.5, 43))
        tail.addQuadCurve(to: point(17, 37), control: point(16, 40))
        context.stroke(tail, with: .color(dog), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))
    }

    /// `TH.shot`: a window with a red "declined" banner and a purple button.
    func screenshot() {
        fill(0, 0, 60, 60, Self.hex(0xE9ECF2))
        let window = Path(roundedRect: rect(5, 7, 50, 46), cornerRadius: 4 * scale)
        context.fill(window, with: .color(.white))
        context.stroke(window, with: .color(Self.hex(0xD1D5DE)), lineWidth: max(0.5, 0.5 * scale))
        circle(10, 11.5, 1.3, Self.hex(0xFF5F57))
        circle(14, 11.5, 1.3, Self.hex(0xFEBC2E))
        circle(18, 11.5, 1.3, Self.hex(0x28C840))
        fill(11, 19, 38, 9, Self.hex(0xFFE4E4), radius: 2)
        fill(14, 22.5, 22, 2.2, Self.hex(0xE5484D), radius: 1)
        fill(11, 33, 26, 2, Self.hex(0xD6D9E0))
        fill(11, 38, 32, 2, Self.hex(0xD6D9E0))
        fill(11, 44, 16, 5, Self.hex(0x635BFF), radius: 2)
    }

    /// `TH.pdf`: a page with a title, lines, a yellow highlight and a red PDF tag.
    func page() {
        fill(0, 0, 60, 60, Self.hex(0xECECF0))
        let sheet = Path(roundedRect: rect(13, 6, 34, 48), cornerRadius: 2 * scale)
        context.fill(sheet, with: .color(.white))
        context.stroke(sheet, with: .color(Self.hex(0xD9D9DE)), lineWidth: max(0.5, 0.5 * scale))
        fill(17, 12, 18, 2.4, Self.hex(0x636366))
        for (y, width) in [(18.0, 26.0), (22.0, 24.0), (26.0, 26.0), (38.0, 22.0), (42.0, 26.0)] {
            fill(17, y, width, 1.5, Self.hex(0xC7C7CC))
        }
        fill(16, 30, 28, 5, Color(red: 1, green: 204 / 255, blue: 0).opacity(0.55), radius: 1)
        fill(36, 47, 9, 4, Self.hex(0xE5484D), radius: 1)
    }
}

#Preview("Samples") {
    HStack(spacing: 10) {
        LookoutSampleThumbnail(sample: .beach)
        LookoutSampleThumbnail(sample: .screenshot)
        LookoutSampleThumbnail(sample: .page)
    }
    .frame(width: 540, height: 70)
    .padding(24)
}
