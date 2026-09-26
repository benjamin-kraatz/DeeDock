import CoreGraphics
import SwiftUI

/// What the pointer does on the picture. `select` moves and edits existing marks; `crop` draws the
/// export selection; every other tool adds one mark per gesture.
nonisolated enum WindowMarkupTool: String, CaseIterable, Identifiable, Sendable {
    case select, pen, highlighter, arrow, rectangle, text, badge, redact, crop

    var id: Self { self }

    var symbol: String {
        switch self {
        case .select: "arrow.up.left.and.down.right.magnifyingglass"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "textformat"
        case .badge: "1.circle.fill"
        case .redact: "eye.slash"
        case .crop: "crop"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .select: .markupToolSelect
        case .pen: .markupToolPen
        case .highlighter: .markupToolHighlighter
        case .arrow: .markupToolArrow
        case .rectangle: .markupToolRectangle
        case .text: .markupToolText
        case .badge: .markupToolBadge
        case .redact: .markupToolRedact
        case .crop: .markupToolCrop
        }
    }

    /// The unmodified key that picks this tool while nothing is being typed.
    var key: Character {
        switch self {
        case .select: "v"
        case .pen: "p"
        case .highlighter: "h"
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .badge: "b"
        case .redact: "x"
        case .crop: "c"
        }
    }

    /// Tools that draw with the chosen colour; redaction and crop have fixed looks.
    var usesColor: Bool { ![.select, .redact, .crop].contains(self) }
}

/// The palette. Colours are fixed rather than free so marks stay legible over any window and the
/// same choice reads the same in the toolbar, the canvas, and the exported file.
nonisolated enum WindowMarkupColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple, white, black

    var id: Self { self }

    var color: Color {
        switch self {
        case .red: Color(red: 1, green: 0.25, blue: 0.2)
        case .orange: Color(red: 1, green: 0.6, blue: 0.1)
        case .yellow: Color(red: 1, green: 0.85, blue: 0.15)
        case .green: Color(red: 0.2, green: 0.8, blue: 0.4)
        case .blue: Color(red: 0.2, green: 0.55, blue: 1)
        case .purple: Color(red: 0.65, green: 0.4, blue: 1)
        case .white: .white
        case .black: Color(white: 0.1)
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .red: .markupColorRed
        case .orange: .markupColorOrange
        case .yellow: .markupColorYellow
        case .green: .markupColorGreen
        case .blue: .markupColorBlue
        case .purple: .markupColorPurple
        case .white: .markupColorWhite
        case .black: .markupColorBlack
        }
    }

    /// Badge numerals and text shadows need a contrasting ink.
    var ink: Color { self == .white || self == .yellow ? Color(white: 0.1) : .white }
}

/// Stroke thickness, text size, and badge size scale together so a "bold" markup reads bold everywhere.
nonisolated enum WindowMarkupWeight: String, CaseIterable, Identifiable, Sendable {
    case thin, regular, bold

    var id: Self { self }

    var multiplier: CGFloat {
        switch self {
        case .thin: 0.65
        case .regular: 1
        case .bold: 1.6
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .thin: .markupWeightThin
        case .regular: .markupWeightRegular
        case .bold: .markupWeightBold
        }
    }
}

/// How a redaction hides pixels. Pixelation keeps the layout legible; solid removes it completely.
nonisolated enum WindowMarkupRedaction: String, Sendable, CaseIterable, Identifiable {
    case pixelate, solid

    var id: Self { self }
}

/// The geometry of one mark, in document pixels with the origin at the picture's top-left corner.
nonisolated enum WindowMarkupShape: Equatable, Sendable {
    case stroke(points: [CGPoint])
    case highlight(points: [CGPoint])
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case text(String, origin: CGPoint)
    case badge(number: Int, center: CGPoint)
    case redact(CGRect, style: WindowMarkupRedaction)

    /// The same shape moved by `delta`, so the select tool can drag any mark.
    func translated(by delta: CGSize) -> WindowMarkupShape {
        func move(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.width, y: point.y + delta.height) }
        switch self {
        case .stroke(let points): return .stroke(points: points.map(move))
        case .highlight(let points): return .highlight(points: points.map(move))
        case .arrow(let from, let to): return .arrow(from: move(from), to: move(to))
        case .rectangle(let rect): return .rectangle(rect.offsetBy(dx: delta.width, dy: delta.height))
        case .text(let string, let origin): return .text(string, origin: move(origin))
        case .badge(let number, let center): return .badge(number: number, center: move(center))
        case .redact(let rect, let style): return .redact(rect.offsetBy(dx: delta.width, dy: delta.height), style: style)
        }
    }
}

/// One mark on the picture. Colour and weight are captured when the mark is made, so changing the
/// palette afterwards does not restyle earlier marks.
nonisolated struct WindowMarkupElement: Identifiable, Equatable, Sendable {
    let id: UUID
    var shape: WindowMarkupShape
    var color: WindowMarkupColor
    var weight: WindowMarkupWeight

    init(id: UUID = UUID(), shape: WindowMarkupShape, color: WindowMarkupColor, weight: WindowMarkupWeight) {
        self.id = id
        self.shape = shape
        self.color = color
        self.weight = weight
    }
}
