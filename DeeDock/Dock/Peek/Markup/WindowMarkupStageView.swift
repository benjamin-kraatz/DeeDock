import SwiftUI

/// The picture, the marks, and every pointer gesture that makes one.
///
/// Gestures are converted to document pixels once, at the picture's top-left corner, so the tools
/// never see points or scale. The stage also owns the opening flight: when the request came from
/// an enlarged preview, the picture starts at that frame and springs into place.
struct WindowMarkupStageView: View {
    let session: WindowMarkupSession
    /// The enlarged preview's frame in the window's top-left-origin space, when there was one.
    let origin: CGRect?
    @Binding var appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var textFocused: Bool
    /// The mark under the pointer when a select drag began, and its shape then.
    @State private var dragging: (id: UUID, shape: WindowMarkupShape)?
    @State private var selectDragMoved = false

    private var document: WindowMarkupDocument { session.document }

    var body: some View {
        GeometryReader { geometry in
            let framed = document.framed
            let padding = framed ? WindowMarkupLayout.framePadding(documentSize: document.size) : 0
            let outer = CGSize(width: document.size.width + 2 * padding, height: document.size.height + 2 * padding)
            let placement = WindowMarkupLayout.pictureFrame(documentSize: outer, stage: geometry.size)
            let scale = placement.scale
            let picture = placement.frame.insetBy(dx: padding * scale, dy: padding * scale)
            let global = geometry.frame(in: .global)
            let flight = flightTransform(picture: picture, stageOrigin: global.origin)
            ZStack(alignment: .topLeading) {
                if framed {
                    WindowMarkupMat(tint: session.tint)
                        .clipShape(.rect(cornerRadius: 8))
                        .frame(width: placement.frame.width, height: placement.frame.height)
                        .offset(x: placement.frame.minX, y: placement.frame.minY)
                        .transition(.opacity)
                }
                pictureLayer(scale: scale)
                    .frame(width: picture.width, height: picture.height)
                    .offset(x: picture.minX, y: picture.minY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .scaleEffect(flight.scale, anchor: .topLeading)
            .offset(flight.offset)
            .opacity(appeared || !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.5, bounce: 0.18), value: appeared)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1), value: document.framed)
        .onChange(of: document.editingTextID) { _, id in textFocused = id != nil }
        .onChange(of: textFocused) { _, focused in if !focused { document.finishText() } }
        .onChange(of: document.tool) { _, tool in
            if tool == .redact { session.preparePixelation() }
            if tool != .text { document.finishText() }
            if tool != .select { document.selectedID = nil }
        }
    }

    /// Before the first frame settles, the picture sits where the enlarged preview was.
    ///
    /// The whole stage is scaled about its top-left corner and shifted, so a stage point `p` lands at
    /// `p * scale + offset`. Solving that for the picture's corner puts it on the origin's corner.
    private func flightTransform(picture: CGRect, stageOrigin: CGPoint) -> (scale: CGFloat, offset: CGSize) {
        // Reduce Motion: no flight, the picture fades in where it belongs.
        guard let origin, !appeared, !reduceMotion, picture.width > 0, picture.height > 0 else { return (1, .zero) }
        let local = origin.offsetBy(dx: -stageOrigin.x, dy: -stageOrigin.y)
        let scale = min(local.width / picture.width, local.height / picture.height)
        return (scale, CGSize(width: local.minX - picture.minX * scale, height: local.minY - picture.minY * scale))
    }

    @ViewBuilder private func pictureLayer(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let image = session.image {
                WindowMarkupPicture(image: image, elements: document.elements, draft: document.draft,
                                    metrics: document.metrics, documentSize: document.size, scale: scale,
                                    pixelated: session.pixelated, selectedID: document.selectedID,
                                    hiddenID: document.editingTextID)
                    .animation(.easeOut(duration: 0.25), value: session.captureState)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay {
                        if let icon = session.appIcon {
                            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                                .frame(width: 96, height: 96).opacity(0.7)
                        }
                    }
            }
            if !document.liveText {
                Color.clear
                    .contentShape(.rect)
                    .gesture(drawing(scale: scale))
                    .pointerStyle(pointer)
            }
            WindowMarkupCropOverlay(document: document, scale: scale, tint: session.tint)
            if document.liveText, let image = session.image {
                WindowMarkupLiveTextView(image: image, session: session)
                    .transition(.opacity)
            }
            textEditor(scale: scale)
        }
        .clipShape(.rect(cornerRadius: document.framed ? document.metrics.unit * 3 * scale : 10))
        .shadow(color: .black.opacity(document.framed ? 0.4 : 0.3), radius: document.framed ? 18 : 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.markupCanvasAccessibility(title: session.title)))
        .accessibilityHint(Text(.markupCanvasAccessibilityHint))
    }

    private var pointer: PointerStyle {
        switch document.tool {
        case .select: dragging == nil ? .grabIdle : .grabActive
        case .crop, .rectangle, .redact: .rectSelection
        case .text: .horizontalText
        default: .default
        }
    }

    // MARK: - Text entry

    @ViewBuilder private func textEditor(scale: CGFloat) -> some View {
        if let id = document.editingTextID, let element = document.element(id),
           case .text(let string, let origin) = element.shape {
            let size = document.metrics.textSize(element.weight) * scale
            TextField(text: Binding(get: { string }, set: { document.setEditingText($0) }), axis: .vertical) {
                Text(.markupTextPlaceholder)
            }
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(element.color.color)
            .shadow(color: element.color.ink.opacity(0.55), radius: size * 0.06, y: size * 0.03)
            .lineLimit(1...6)
            .frame(width: max(120, (document.size.width - origin.x) * scale - 8), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .focused($textFocused)
            .onSubmit { document.finishText() }
            .onExitCommand { document.finishText() }
            // A text field draws its own baseline inset; align the glyphs with the canvas rendering.
            .offset(x: origin.x * scale - 2, y: origin.y * scale - size * 0.14)
            .onAppear { textFocused = true }
        }
    }

    // MARK: - Drawing

    private func drawing(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = documentPoint(value.location, scale: scale)
                let start = documentPoint(value.startLocation, scale: scale)
                switch document.tool {
                case .pen, .highlighter:
                    if var draft = document.draft {
                        switch draft.shape {
                        case .stroke(var points): points.append(point); draft.shape = .stroke(points: points)
                        case .highlight(var points): points.append(point); draft.shape = .highlight(points: points)
                        default: break
                        }
                        document.draft = draft
                    } else {
                        let shape: WindowMarkupShape = document.tool == .pen ? .stroke(points: [start]) : .highlight(points: [start])
                        document.draft = WindowMarkupElement(shape: shape, color: document.color, weight: document.weight)
                    }
                case .arrow:
                    document.draft = WindowMarkupElement(shape: .arrow(from: start, to: point), color: document.color,
                                                         weight: document.weight)
                case .rectangle:
                    document.draft = WindowMarkupElement(shape: .rectangle(WindowMarkupGeometry.rect(from: start, to: point)),
                                                         color: document.color, weight: document.weight)
                case .redact:
                    document.draft = WindowMarkupElement(shape: .redact(WindowMarkupGeometry.rect(from: start, to: point),
                                                                        style: document.redaction),
                                                         color: document.color, weight: document.weight)
                case .crop:
                    document.crop = WindowMarkupGeometry.clampedCrop(WindowMarkupGeometry.rect(from: start, to: point),
                                                                     in: document.size) ?? document.crop
                case .select:
                    selectMoved(start: start, point: point, translation: value.translation, scale: scale)
                case .text, .badge:
                    break
                }
            }
            .onEnded { value in
                let point = documentPoint(value.location, scale: scale)
                let tapped = hypot(value.translation.width, value.translation.height) < 3
                switch document.tool {
                case .pen, .highlighter, .arrow, .rectangle, .redact:
                    if let draft = document.draft, keeps(draft) { document.commit(draft) }
                    document.draft = nil
                case .badge:
                    guard tapped else { return }
                    document.commit(WindowMarkupElement(shape: .badge(number: document.nextBadgeNumber, center: point),
                                                        color: document.color, weight: document.weight))
                case .text:
                    guard tapped else { return }
                    if document.editingTextID != nil { document.finishText() } else { document.beginText(at: point) }
                case .select:
                    selectEnded(point: point, tapped: tapped)
                case .crop:
                    break
                }
            }
    }

    private func documentPoint(_ location: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: min(max(location.x / scale, 0), document.size.width),
                y: min(max(location.y / scale, 0), document.size.height))
    }

    /// Accidental taps with a shape tool leave nothing behind.
    private func keeps(_ draft: WindowMarkupElement) -> Bool {
        switch draft.shape {
        case .stroke, .highlight: return true
        case .arrow(let from, let to): return hypot(to.x - from.x, to.y - from.y) >= 3
        case .rectangle(let rect), .redact(let rect, _): return rect.width >= 3 && rect.height >= 3
        case .text, .badge: return false
        }
    }

    private func selectMoved(start: CGPoint, point: CGPoint, translation: CGSize, scale: CGFloat) {
        if dragging == nil {
            selectDragMoved = false
            guard let id = WindowMarkupGeometry.hit(start, in: document.elements, metrics: document.metrics),
                  let element = document.element(id) else {
                document.selectedID = nil
                return
            }
            document.selectedID = id
            dragging = (id, element.shape)
        }
        guard let dragging else { return }
        let delta = CGSize(width: translation.width / scale, height: translation.height / scale)
        guard abs(delta.width) + abs(delta.height) > 0.5 else { return }
        // One undo step per drag: the first move records, the rest continue it.
        document.update(dragging.id, shape: dragging.shape.translated(by: delta), continuing: selectDragMoved)
        selectDragMoved = true
    }

    private func selectEnded(point: CGPoint, tapped: Bool) {
        defer { dragging = nil; selectDragMoved = false }
        guard tapped else { return }
        let previous = document.selectedID
        let hit = WindowMarkupGeometry.hit(point, in: document.elements, metrics: document.metrics)
        document.selectedID = hit
        // A second click on a selected text mark reopens it for typing.
        if let hit, hit == previous { document.reopenText(hit) }
    }
}
