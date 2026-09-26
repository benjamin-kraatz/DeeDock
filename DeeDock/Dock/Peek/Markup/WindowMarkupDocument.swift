import CoreGraphics
import Foundation
import Observation

/// The marks on one captured window and the editing state around them.
///
/// Coordinates are document pixels: a fixed space the size of the full-resolution capture, so a
/// mark drawn over the quick preview lands on the same spot once the sharp capture arrives. Undo is
/// snapshot based, which keeps every edit reversible without per-operation inverse logic.
@MainActor @Observable
final class WindowMarkupDocument {
    /// The fixed pixel size of the picture, and therefore of the export.
    let size: CGSize
    let metrics: WindowMarkupMetrics
    private(set) var elements: [WindowMarkupElement] = []
    private var undoStack: [[WindowMarkupElement]] = []
    private var redoStack: [[WindowMarkupElement]] = []
    var tool: WindowMarkupTool = .pen
    var color: WindowMarkupColor = .red
    var weight: WindowMarkupWeight = .regular
    var redaction: WindowMarkupRedaction = .pixelate
    /// The mark being drawn right now; committed on release.
    var draft: WindowMarkupElement?
    /// The export selection, in document pixels; `nil` exports the whole picture.
    var crop: CGRect?
    var selectedID: UUID?
    /// The text mark whose string is being typed. Set through `beginText(at:)` or `reopenText(_:)`.
    private(set) var editingTextID: UUID?
    /// Whether the mark being typed was created by `beginText(at:)` and is not yet a real mark.
    private var editingIsNew = false
    /// The reopened mark's string when editing began, so an unchanged edit leaves no undo step.
    private var editingOriginal: String?
    /// Wraps the export in a coloured mat with rounded corners.
    var framed = false
    /// Live Text mode: the VisionKit overlay takes the pointer instead of the drawing tools.
    var liveText = false

    init(size: CGSize) {
        self.size = size
        metrics = WindowMarkupMetrics(documentSize: size)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasMarks: Bool { !elements.isEmpty }
    var hasRedactions: Bool {
        elements.contains { if case .redact = $0.shape { return true } else { return false } }
    }
    var nextBadgeNumber: Int {
        (elements.compactMap { element -> Int? in
            if case .badge(let number, _) = element.shape { return number }
            return nil
        }.max() ?? 0) + 1
    }

    func element(_ id: UUID) -> WindowMarkupElement? { elements.first { $0.id == id } }

    /// Adds a finished mark. Empty text is dropped rather than left as an invisible mark.
    func commit(_ element: WindowMarkupElement) {
        if case .text(let string, _) = element.shape, string.isEmpty { return }
        record()
        elements.append(element)
    }

    /// Replaces a mark's shape, recording one undo step unless `continuing` a drag already recorded.
    func update(_ id: UUID, shape: WindowMarkupShape, continuing: Bool = false) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        if !continuing { record() }
        elements[index].shape = shape
    }

    /// Restyles a mark in place, used when the palette changes while a mark is selected.
    func restyle(_ id: UUID, color: WindowMarkupColor? = nil, weight: WindowMarkupWeight? = nil) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        record()
        if let color { elements[index].color = color }
        if let weight { elements[index].weight = weight }
    }

    func remove(_ id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        record()
        elements.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        if editingTextID == id { editingTextID = nil }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = previous
        clearTransient()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
        clearTransient()
    }

    func clear() {
        guard hasMarks else { return }
        record()
        elements = []
        clearTransient()
    }

    /// Adds a text mark at `origin` and starts typing into it.
    func beginText(at origin: CGPoint) {
        let element = WindowMarkupElement(shape: .text("", origin: origin), color: color, weight: weight)
        record()
        elements.append(element)
        editingTextID = element.id
        editingIsNew = true
        editingOriginal = nil
        selectedID = element.id
    }

    /// Starts typing into an existing text mark. The edit becomes one undo step when it changes
    /// the string; clearing the string removes the mark, and that removal is undoable.
    func reopenText(_ id: UUID) {
        guard editingTextID == nil, let element = element(id), case .text(let string, _) = element.shape else { return }
        record()
        editingTextID = id
        editingIsNew = false
        editingOriginal = string
        selectedID = id
    }

    /// Stores the typed string. A new mark left empty disappears together with its undo step; a
    /// reopened mark left unchanged drops the step it recorded, so undo never replays a no-op.
    func finishText() {
        guard let id = editingTextID else { return }
        let isNew = editingIsNew
        let original = editingOriginal
        editingTextID = nil
        editingIsNew = false
        editingOriginal = nil
        guard let element = element(id), case .text(let string, _) = element.shape else { return }
        let empty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty {
            elements.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
            // The step recorded when the new mark was created captured a state without it: pop it.
            if isNew { _ = undoStack.popLast() }
        } else if !isNew, string == original {
            _ = undoStack.popLast()
        }
    }

    /// Sets the text of the mark being edited without an undo step per keystroke.
    func setEditingText(_ string: String) {
        guard let id = editingTextID, let index = elements.firstIndex(where: { $0.id == id }),
              case .text(_, let origin) = elements[index].shape else { return }
        elements[index].shape = .text(string, origin: origin)
    }

    /// Selected-mark ids are only meaningful while the mark exists.
    private func clearTransient() {
        draft = nil
        if let selectedID, !elements.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        if let editingTextID, !elements.contains(where: { $0.id == editingTextID }) { self.editingTextID = nil }
    }

    private func record() {
        undoStack.append(elements)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
}
