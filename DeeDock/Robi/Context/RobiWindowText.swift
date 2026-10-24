import ApplicationServices
import Foundation

/// Reads the visible text of the frontmost app's focused window from its accessibility tree.
///
/// Runs off the main actor: some apps answer AX slowly (a full walk of Finder or System Settings
/// took over a second in the spike), so the walk is bounded by time and length and never blocks
/// the main thread. Terminal text views such as Ghostty's hold the whole visible screen in one
/// `AXTextArea` value, which is read without descending further.
nonisolated enum RobiWindowText {
    static func read(processIdentifier: pid_t, budget: TimeInterval = 0.4, limit: Int = 16_000) async -> String {
        await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let window = RobiAX.element(application, kAXFocusedWindowAttribute) else { return "" }
            let deadline = Date().addingTimeInterval(budget)
            var pieces: [String] = []
            var total = 0
            var queue: [AXUIElement] = [window]
            var index = 0
            while index < queue.count, Date() < deadline, total < limit, !Task.isCancelled {
                let element = queue[index]
                index += 1
                let role = RobiAX.value(element, kAXRoleAttribute) as? String ?? ""
                if ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading"].contains(role) {
                    for key in [kAXValueAttribute, kAXTitleAttribute] {
                        if let text = RobiAX.value(element, key) as? String, !text.isEmpty {
                            pieces.append(text)
                            total += text.count
                            break
                        }
                    }
                    if role == "AXTextArea" { continue }
                }
                queue.append(contentsOf: RobiAX.children(element))
            }
            return String(pieces.joined(separator: "\n").prefix(limit))
        }.value
    }
}
