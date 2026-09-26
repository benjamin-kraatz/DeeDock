import SwiftUI

/// Draws marks over a picture displayed at `scale` points per document pixel.
///
/// Paths are built in document pixels and scaled explicitly, and text is resolved at the scaled
/// size, so the editor at any zoom and the export at scale 1 render the same picture. It is a
/// `Canvas`, so a 200-point pen stroke costs one redraw rather than a view per point.
struct WindowMarkupCanvas: View {
    let elements: [WindowMarkupElement]
    let draft: WindowMarkupElement?
    let metrics: WindowMarkupMetrics
    let scale: CGFloat
    /// The coarse copy redactions reveal; a solid fill stands in until it exists.
    let pixelated: CGImage?
    let documentSize: CGSize
    var selectedID: UUID? = nil
    /// The text mark being typed lives in a text field instead, so the canvas skips it.
    var hiddenID: UUID? = nil

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            for element in elements where element.id != hiddenID {
                draw(element, in: &context)
            }
            if let draft { draw(draft, in: &context) }
            if let selectedID, let element = elements.first(where: { $0.id == selectedID }) {
                drawSelection(around: element, in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var transform: CGAffineTransform { CGAffineTransform(scaleX: scale, y: scale) }

    private func draw(_ element: WindowMarkupElement, in context: inout GraphicsContext) {
        let color = element.color.color
        let weight = element.weight
        switch element.shape {
        case .stroke(let points):
            context.stroke(WindowMarkupGeometry.strokePath(points).applying(transform), with: .color(color),
                           style: StrokeStyle(lineWidth: metrics.penWidth(weight) * scale, lineCap: .round, lineJoin: .round))
        case .highlight(let points):
            var layer = context
            layer.blendMode = .multiply
            layer.opacity = 0.55
            layer.stroke(WindowMarkupGeometry.strokePath(points).applying(transform), with: .color(color),
                         style: StrokeStyle(lineWidth: metrics.highlightWidth(weight) * scale, lineCap: .round, lineJoin: .round))
        case .arrow(let from, let to):
            let head = metrics.arrowHead(weight)
            context.stroke(WindowMarkupGeometry.arrowShaft(from: from, to: to, head: head).applying(transform),
                           with: .color(color),
                           style: StrokeStyle(lineWidth: metrics.arrowWidth(weight) * scale, lineCap: .round))
            context.fill(WindowMarkupGeometry.arrowHead(from: from, to: to, head: head).applying(transform), with: .color(color))
        case .rectangle(let rect):
            let path = Path(roundedRect: rect, cornerRadius: metrics.rectangleRadius).applying(transform)
            context.stroke(path, with: .color(color), lineWidth: metrics.rectangleWidth(weight) * scale)
        case .text(let string, let origin):
            let size = metrics.textSize(weight) * scale
            let text = Text(verbatim: string).font(.system(size: size, weight: .semibold, design: .rounded))
            var shadowed = context
            shadowed.addFilter(.shadow(color: element.color.ink.opacity(0.55), radius: size * 0.06, y: size * 0.03))
            shadowed.draw(text.foregroundStyle(color), at: CGPoint(x: origin.x * scale, y: origin.y * scale), anchor: .topLeading)
        case .badge(let number, let center):
            let radius = metrics.badgeRadius(weight) * scale
            let rect = CGRect(x: center.x * scale - radius, y: center.y * scale - radius, width: 2 * radius, height: 2 * radius)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: radius * 0.25, y: radius * 0.1))
            shadowed.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: radius * 0.08, dy: radius * 0.08)),
                           with: .color(element.color.ink.opacity(0.9)), lineWidth: max(1, radius * 0.12))
            context.draw(Text(verbatim: "\(number)").font(.system(size: radius * 1.15, weight: .bold, design: .rounded))
                .foregroundStyle(element.color.ink), at: CGPoint(x: rect.midX, y: rect.midY))
        case .redact(let rect, let style):
            let scaled = rect.applying(transform)
            if style == .pixelate, let pixelated {
                context.drawLayer { layer in
                    layer.clip(to: Path(scaled))
                    layer.draw(Image(decorative: pixelated, scale: 1),
                               in: CGRect(origin: .zero, size: CGSize(width: documentSize.width * scale,
                                                                       height: documentSize.height * scale)))
                }
            } else {
                context.fill(Path(scaled), with: .color(Color(white: 0.08)))
            }
        }
    }

    private func drawSelection(around element: WindowMarkupElement, in context: inout GraphicsContext) {
        let bounds = WindowMarkupGeometry.bounds(of: element, metrics: metrics).applying(transform).insetBy(dx: -4, dy: -4)
        let path = Path(roundedRect: bounds, cornerRadius: 5)
        context.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
        context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }
}

/// The picture with its marks, at any scale. The editor overlays gestures on it; the export renders it.
struct WindowMarkupPicture: View {
    let image: CGImage
    let elements: [WindowMarkupElement]
    let draft: WindowMarkupElement?
    let metrics: WindowMarkupMetrics
    let documentSize: CGSize
    let scale: CGFloat
    let pixelated: CGImage?
    var selectedID: UUID? = nil
    var hiddenID: UUID? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The capture may be a few pixels off the document size; stretching hides the rounding.
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: documentSize.width * scale, height: documentSize.height * scale)
            WindowMarkupCanvas(elements: elements, draft: draft, metrics: metrics, scale: scale,
                               pixelated: pixelated, documentSize: documentSize, selectedID: selectedID, hiddenID: hiddenID)
        }
        .frame(width: documentSize.width * scale, height: documentSize.height * scale)
    }
}

/// The exported image: the cropped picture, optionally on a coloured mat. Rendered at scale 1 by
/// `ImageRenderer`, so one point here is one pixel in the file.
struct WindowMarkupComposite: View {
    let image: CGImage
    let elements: [WindowMarkupElement]
    let metrics: WindowMarkupMetrics
    let documentSize: CGSize
    let crop: CGRect?
    let pixelated: CGImage?
    let framed: Bool
    let tint: Color

    /// The output size in pixels for these inputs.
    static func outputSize(documentSize: CGSize, crop: CGRect?, framed: Bool) -> CGSize {
        let picture = crop?.size ?? documentSize
        guard framed else { return picture }
        let padding = WindowMarkupLayout.framePadding(documentSize: documentSize)
        return CGSize(width: picture.width + 2 * padding, height: picture.height + 2 * padding)
    }

    var body: some View {
        let pictureRect = crop ?? CGRect(origin: .zero, size: documentSize)
        let picture = WindowMarkupPicture(image: image, elements: elements, draft: nil, metrics: metrics,
                                          documentSize: documentSize, scale: 1, pixelated: pixelated)
            .offset(x: -pictureRect.minX, y: -pictureRect.minY)
            .frame(width: pictureRect.width, height: pictureRect.height, alignment: .topLeading)
            .clipped()
        if framed {
            let padding = WindowMarkupLayout.framePadding(documentSize: documentSize)
            picture
                .clipShape(.rect(cornerRadius: metrics.unit * 3))
                .shadow(color: .black.opacity(0.35), radius: padding * 0.35, y: padding * 0.18)
                .padding(padding)
                .background(WindowMarkupMat(tint: tint))
        } else {
            picture
        }
    }
}

/// The presentation frame's background: the app's accent, softened into a diagonal wash.
struct WindowMarkupMat: View {
    let tint: Color

    var body: some View {
        LinearGradient(colors: [tint.opacity(0.95), tint.mix(with: .white, by: 0.35), tint.mix(with: .black, by: 0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
