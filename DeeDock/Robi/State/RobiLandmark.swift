import CoreGraphics
import Foundation

/// One thing Robi read in a window, with where it is, so an answer can point at it.
///
/// Landmarks come from the accessibility tree (text, headings, buttons, links, fields) or, when
/// Robi read a picture, from the lines Vision recognized in it. The model sees each one as a
/// numbered line and links the ones it mentions as `[words](#id)`; clicking such a link in the
/// card spotlights `frame` on the window.
nonisolated struct RobiLandmark: Equatable, Sendable, Identifiable {
    /// Unique within one context, starting at 1, in reading order.
    let id: Int
    let kind: Kind
    /// The element's text, title or description. Untrusted, like all context.
    let label: String
    /// Window-local top-left points: the origin is the window's top-left corner, as AX and the
    /// window server report it when the context was read. Always inside the window's bounds.
    let frame: CGRect

    /// What sort of element a landmark is, named for the model in `RobiAgent`.
    enum Kind: String, Sendable {
        case text, textArea = "text area", field, heading, button, link, checkbox, option, popUp = "pop-up"
        case menuButton = "menu button", image

        /// The kind for an AX role, or nil for roles Robi does not list.
        init?(role: String) {
            switch role {
            case "AXStaticText": self = .text
            case "AXTextArea": self = .textArea
            case "AXTextField", "AXComboBox": self = .field
            case "AXHeading": self = .heading
            case "AXButton": self = .button
            case "AXLink": self = .link
            case "AXCheckBox", "AXSwitch": self = .checkbox
            case "AXRadioButton": self = .option
            case "AXPopUpButton": self = .popUp
            case "AXMenuButton": self = .menuButton
            case "AXImage": self = .image
            default: return nil
            }
        }

        /// Fields and text areas, whose text a step may replace.
        var isEditable: Bool { self == .field || self == .textArea }

        /// Controls are labelled by their title or description and read as a whole; their
        /// children usually repeat the label.
        var isControl: Bool {
            switch self {
            case .button, .link, .checkbox, .option, .popUp, .menuButton, .image: true
            case .text, .textArea, .field, .heading: false
            }
        }
    }

    /// Moves a global top-left frame into the window's space and keeps the part inside the
    /// window. Nil when nothing of it is visible in the window, such as content scrolled away,
    /// which AX still reports with a frame outside the window.
    static func windowLocal(_ global: CGRect, window: CGRect) -> CGRect? {
        let local = global.offsetBy(dx: -window.minX, dy: -window.minY)
        let visible = local.intersection(CGRect(origin: .zero, size: window.size))
        guard !visible.isNull, visible.width >= 2, visible.height >= 2 else { return nil }
        return visible
    }

    /// Landmarks for lines Vision recognized in a picture of `source`, a rect in window-local
    /// top-left points (the whole window, or the region the person dragged).
    ///
    /// Vision's boxes are normalized to the picture with the origin at the lower left; the y axis
    /// flips here, and the picture's pixel scale drops out because the boxes are fractions.
    static func recognized(_ lines: [RobiRecognizedLine], in source: CGRect) -> [RobiLandmark] {
        var result: [RobiLandmark] = []
        for line in lines {
            let box = line.box
            let frame = CGRect(x: source.minX + box.minX * source.width,
                               y: source.minY + (1 - box.maxY) * source.height,
                               width: box.width * source.width, height: box.height * source.height)
            let label = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, frame.width >= 1, frame.height >= 1 else { continue }
            result.append(RobiLandmark(id: result.count + 1, kind: .text, label: label, frame: frame))
        }
        return result
    }
}

/// A line of text Vision recognized, with its box normalized to the picture (0…1, lower-left origin).
nonisolated struct RobiRecognizedLine: Equatable, Sendable {
    let text: String
    let box: CGRect
}
