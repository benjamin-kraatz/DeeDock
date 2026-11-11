import CoreGraphics
import SwiftUI

/// Vapor's small folder drawing, for the icons tumbling inside the orb and on the bubbles.
///
/// The system folder icon has a low tab and little contrast, so at 20–35 pt and rotated it
/// reads as a plain blue tile. This follows the mockup's sprite instead: a darker back with a
/// clear tab, a lighter front, a highlight along the front's top edge, and a soft dark edge so
/// overlapping folders separate. Panel rows are large enough for the real system icon and keep
/// it (``VaporFolderIcon``).
///
/// Drawn once into a bitmap, since the orb's canvas draws many copies per frame.
enum VaporFolderGlyph {
    /// The folder artwork's box, in the mockup's units.
    static let artSize = CGSize(width: 32, height: 26)
    /// Transparent room around the artwork inside the bitmap, for the soft edge.
    static let margin: CGFloat = 2
    /// Bitmap pixels per unit: enough for a 36 pt wide folder on a 3× display.
    private static let pixelsPerUnit: CGFloat = 4

    /// The rect to draw ``image`` into so the folder artwork is `width` points wide and centred
    /// on `center`.
    static func rect(artWidth width: CGFloat, center: CGPoint = .zero) -> CGRect {
        let unit = width / artSize.width
        let size = CGSize(width: (artSize.width + margin * 2) * unit, height: (artSize.height + margin * 2) * unit)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    static let image: Image = {
        let scale = pixelsPerUnit
        let width = Int((artSize.width + margin * 2) * scale), height = Int((artSize.height + margin * 2) * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Image(systemName: "folder.fill")
        }
        // Work in the mockup's units with y pointing down, like the SVG paths this follows.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: margin, y: margin)
        draw(in: context, space: space, scale: scale)
        guard let image = context.makeImage() else { return Image(systemName: "folder.fill") }
        return Image(decorative: image, scale: 1)
    }()

    private static func draw(in context: CGContext, space: CGColorSpace, scale: CGFloat) {
        let back = backPath, front = CGPath(roundedRect: CGRect(x: 1, y: 6, width: 30, height: 19),
                                            cornerWidth: 3, cornerHeight: 3, transform: nil)
        func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [red / 255, green / 255, blue / 255, alpha]) ?? .black
        }
        func fill(_ path: CGPath, from top: CGColor, to bottom: CGColor, minY: CGFloat, maxY: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) else { return }
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: minY), end: CGPoint(x: 0, y: maxY), options: [])
            context.restoreGState()
        }

        // A soft dark edge all round (not a directional shadow: the icons rotate).
        context.saveGState()
        context.setShadow(offset: .zero, blur: 1.1 * scale, color: color(6, 30, 70, 0.45))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color(47, 134, 218))
        context.addPath(back)
        context.addPath(front)
        context.fillPath()
        context.endTransparencyLayer()
        context.restoreGState()

        fill(back, from: color(74, 160, 232), to: color(36, 116, 200), minY: 1.5, maxY: 25)
        // The front casts a little shade on the back where they meet, which is what makes the tab read.
        context.saveGState()
        context.addPath(back)
        context.clip()
        context.setShadow(offset: CGSize(width: 0, height: 0.7 * scale), blur: 1.2 * scale, color: color(10, 50, 110, 0.55))
        context.setFillColor(color(74, 166, 242))
        context.addPath(front)
        context.fillPath()
        context.restoreGState()
        fill(front, from: color(156, 216, 255), to: color(70, 160, 240), minY: 6, maxY: 25)

        context.setLineCap(.round)
        context.setStrokeColor(color(255, 255, 255, 0.7))
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: 4, y: 6.8))
        context.addLine(to: CGPoint(x: 28, y: 6.8))
        context.strokePath()

        // A thin darker outline, so two overlapping folders of the same blue keep their shapes.
        context.setStrokeColor(color(18, 84, 164, 0.42))
        context.setLineWidth(0.5)
        context.addPath(back)
        context.strokePath()
        context.setStrokeColor(color(18, 84, 164, 0.32))
        context.addPath(front)
        context.strokePath()
    }

    /// The folder's back with its tab, from the mockup's SVG path.
    private static var backPath: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 4.5))
        path.addArc(tangent1End: CGPoint(x: 1, y: 1.5), tangent2End: CGPoint(x: 4, y: 1.5), radius: 3)
        path.addLine(to: CGPoint(x: 11.6, y: 1.5))
        path.addCurve(to: CGPoint(x: 13.6, y: 2.4), control1: CGPoint(x: 12.4, y: 1.5), control2: CGPoint(x: 13.1, y: 1.8))
        path.addLine(to: CGPoint(x: 15.2, y: 4.1))
        path.addLine(to: CGPoint(x: 28, y: 4.1))
        path.addArc(tangent1End: CGPoint(x: 31, y: 4.1), tangent2End: CGPoint(x: 31, y: 7.1), radius: 3)
        path.addLine(to: CGPoint(x: 31, y: 22))
        path.addArc(tangent1End: CGPoint(x: 31, y: 25), tangent2End: CGPoint(x: 28, y: 25), radius: 3)
        path.addLine(to: CGPoint(x: 4, y: 25))
        path.addArc(tangent1End: CGPoint(x: 1, y: 25), tangent2End: CGPoint(x: 1, y: 22), radius: 3)
        path.closeSubpath()
        return path
    }
}

/// ``VaporFolderGlyph`` as a view, `width` points wide.
struct VaporFolderGlyphView: View {
    var width: CGFloat

    var body: some View {
        let rect = VaporFolderGlyph.rect(artWidth: width)
        VaporFolderGlyph.image
            .resizable()
            .interpolation(.high)
            .frame(width: rect.width, height: rect.height)
            // Lay out as the artwork alone; the soft edge overhangs.
            .padding(-VaporFolderGlyph.margin * width / VaporFolderGlyph.artSize.width)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Folder glyph sizes") {
    HStack(spacing: 14) {
        ForEach([18.0, 24, 30, 36, 64], id: \.self) { width in
            VaporFolderGlyphView(width: width)
        }
        VaporFolderGlyphView(width: 30).rotationEffect(.degrees(-24))
    }
    .padding(30)
    .background(VaporPreviewBackdrop())
}
#endif
