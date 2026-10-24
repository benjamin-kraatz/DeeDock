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
nonisolated enum RobiWindowText {
    /// The window's text joined by line, and the landmarks it came from.
    struct Reading: Sendable {
        var text: String
        var landmarks: [RobiLandmark]
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
                        landmarks.append(RobiLandmark(id: landmarks.count + 1, kind: kind, label: text, frame: frame))
                    }
                    if kind == .textArea || kind.isControl { continue }
                }
                queue.append(contentsOf: RobiAX.children(element))
            }
            return Reading(text: String(pieces.joined(separator: "\n").prefix(limit)), landmarks: landmarks)
        }.value
    }

    /// Text reads its value, then its title; a control its title, then its description. Nil when
    /// the element has nothing to say, so an unlabelled control is descended into instead.
    private static func label(of element: AXUIElement, kind: RobiLandmark.Kind) -> String? {
        let keys = kind.isControl ? [kAXTitleAttribute, kAXDescriptionAttribute] : [kAXValueAttribute, kAXTitleAttribute]
        for key in keys {
            if let text = RobiAX.value(element, key) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return kind.isControl ? String(trimmed.prefix(120)) : text }
            }
        }
        return nil
    }
}
