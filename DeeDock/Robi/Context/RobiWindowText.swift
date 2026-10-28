import ApplicationServices
import Foundation

/// Reads the visible text and controls of the frontmost app's focused window from its
/// accessibility tree, each with where it sits in the window.
///
/// Runs off the main actor: some apps answer AX slowly (a full walk of Finder or System Settings
/// took over a second in the spike), so the walk is bounded by time and length and never blocks
/// the main thread. Terminal text views such as Ghostty's hold the whole visible screen in one
/// `AXTextArea` value, which is read without descending further. A labelled control (a button, a
/// link) is read by its label without its children, which usually repeat it; an unlabelled one is
/// descended into, so a web link's text still counts.
///
/// The elements Robi can act on (buttons, links, checkboxes, options, and fields whose text can be
/// set) are kept by landmark number, so a step the model proposes refers to the very element that
/// was read rather than to whatever sits at its position later.
nonisolated enum RobiWindowText {
    /// The window's text joined by line, the landmarks it came from, and the elements Robi can act on.
    struct Reading: @unchecked Sendable {
        var text: String
        var landmarks: [RobiLandmark]
        var elements: [Int: AXUIElement] = [:]
    }

    static func read(processIdentifier: pid_t, budget: TimeInterval = 0.4, limit: Int = 16_000,
                     landmarkLimit: Int = 500) async -> Reading {
        await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let window = RobiAX.element(application, kAXFocusedWindowAttribute) else { return Reading(text: "", landmarks: []) }
            // Landmarks are relative to the window as AX reports it now, the same frame the
            // tracker uses, so the spotlight lines up with the window it covers.
            let windowFrame = RobiAX.frame(of: window)
            let deadline = Date().addingTimeInterval(budget)
            var pieces: [String] = []
            var landmarks: [RobiLandmark] = []
            var elements: [Int: AXUIElement] = [:]
            var total = 0
            var queue: [AXUIElement] = [window]
            var index = 0
            while index < queue.count, Date() < deadline, total < limit, !Task.isCancelled {
                let element = queue[index]
                index += 1
                let role = RobiAX.value(element, kAXRoleAttribute) as? String ?? ""
                if let kind = RobiLandmark.Kind(role: role), let text = label(of: element, kind: kind) {
                    pieces.append(text)
                    total += text.count
                    if landmarks.count < landmarkLimit, let windowFrame, let global = RobiAX.frame(of: element),
                       let frame = RobiLandmark.windowLocal(global, window: windowFrame) {
                        let landmark = RobiLandmark(id: landmarks.count + 1, kind: kind, label: text, frame: frame)
                        landmarks.append(landmark)
                        if isActionable(element, kind: kind) { elements[landmark.id] = element }
                    }
                    if kind == .textArea || kind.isControl { continue }
                }
                queue.append(contentsOf: RobiAX.children(element))
            }
            return Reading(text: String(pieces.joined(separator: "\n").prefix(limit)), landmarks: landmarks, elements: elements)
        }.value
    }

    /// Text reads its value, then its title; a control its title, then its description. An empty
    /// field reads its placeholder or description instead, such as "Search", so the model can
    /// still find it to type into. A control or field with none of these reads the label beside
    /// it that names it (`AXTitleUIElement`): a switch in a SwiftUI form or System Settings has no
    /// title of its own. Nil when the element has nothing to say, so an unlabelled control is
    /// descended into instead.
    static func label(of element: AXUIElement, kind: RobiLandmark.Kind) -> String? {
        if let own = ownLabel(of: element, kind: kind) { return own }
        guard kind.isControl || kind.isEditable,
              let title = RobiAX.element(element, kAXTitleUIElementAttribute),
              let text = (RobiAX.value(title, kAXValueAttribute) ?? RobiAX.value(title, kAXTitleAttribute)) as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    private static func ownLabel(of element: AXUIElement, kind: RobiLandmark.Kind) -> String? {
        let keys = if kind.isControl {
            [kAXTitleAttribute, kAXDescriptionAttribute]
        } else if kind.isEditable {
            [kAXValueAttribute, kAXPlaceholderValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
        } else {
            [kAXValueAttribute, kAXTitleAttribute]
        }
        for key in keys {
            if let text = RobiAX.value(element, key) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return kind.isControl ? String(trimmed.prefix(120)) : text }
            }
        }
        return nil
    }

    /// Whether a step may act on the element: a control it can press or toggle, or a field whose
    /// text it can set. Pop-ups and menu buttons are left out, since pressing one only opens a
    /// menu that the next step could not choose from.
    private static func isActionable(_ element: AXUIElement, kind: RobiLandmark.Kind) -> Bool {
        switch kind {
        case .button, .link, .checkbox, .option: true
        case .field, .textArea: RobiAX.isSettable(element, kAXValueAttribute)
        case .text, .heading, .popUp, .menuButton, .image: false
        }
    }
}
