import ApplicationServices
import Foundation
import FoundationModels

/// The frontmost app's menu bar as a list of commands Robi can propose.
///
/// Every Mac app exposes its menus through Accessibility, Electron apps included, so this is the
/// one action surface that works everywhere. The spike counted 150 to 761 items per app, read in
/// 100 to 230 ms (Ghostty took 2.2 s), so the walk is bounded and runs off the main actor.
nonisolated enum RobiMenuCommands {
    static let separator = " > "

    /// Enabled leaf items as "Menu > Item" paths, skipping the Apple menu.
    static func list(processIdentifier: pid_t, limit: Int = 140, budget: TimeInterval = 0.5) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let bar = RobiAX.element(application, kAXMenuBarAttribute) else { return [] }
            let deadline = Date().addingTimeInterval(budget)
            var result: [String] = []
            for top in RobiAX.children(bar).dropFirst() {
                guard let title = RobiAX.value(top, kAXTitleAttribute) as? String, !title.isEmpty else { continue }
                walk(top, path: [title], into: &result, limit: limit, deadline: deadline)
                if result.count >= limit || Date() > deadline { break }
            }
            return result
        }.value
    }

    private static func walk(_ element: AXUIElement, path: [String], into result: inout [String], limit: Int, deadline: Date) {
        for child in RobiAX.children(element) {
            guard result.count < limit, Date() <= deadline else { return }
            let role = RobiAX.value(child, kAXRoleAttribute) as? String
            if role == "AXMenu" {
                walk(child, path: path, into: &result, limit: limit, deadline: deadline)
                continue
            }
            guard role == "AXMenuItem", let title = RobiAX.value(child, kAXTitleAttribute) as? String, !title.isEmpty else { continue }
            if let submenu = RobiAX.children(child).first(where: { (RobiAX.value($0, kAXRoleAttribute) as? String) == "AXMenu" }) {
                walk(submenu, path: path + [title], into: &result, limit: limit, deadline: deadline)
            } else if (RobiAX.value(child, kAXEnabledAttribute) as? Bool) == true {
                result.append((path + [title]).joined(separator: separator))
            }
        }
    }

    /// Presses the item at `path` if it still exists and is enabled.
    @MainActor
    static func press(processIdentifier: pid_t, path: String) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard var current = RobiAX.element(application, kAXMenuBarAttribute) else { return false }
        for part in path.components(separatedBy: separator) {
            var candidates = RobiAX.children(current)
            if let menu = candidates.first(where: { (RobiAX.value($0, kAXRoleAttribute) as? String) == "AXMenu" }) {
                candidates = RobiAX.children(menu)
            }
            guard let next = candidates.first(where: { (RobiAX.value($0, kAXTitleAttribute) as? String) == part }) else { return false }
            current = next
        }
        guard (RobiAX.value(current, kAXEnabledAttribute) as? Bool) != false else { return false }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
    }
}

/// Lets the model propose one menu command. It never runs anything: the proposal appears as a
/// button in the answer card and runs only when the person clicks it.
nonisolated struct RobiProposeMenuCommand: Tool {
    let name = "propose_menu_command"
    let description = "Propose one of the app's menu commands for the person to run. Use it only when they ask you to do something in the app, and only with an exact path from the list."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The exact menu path from the list, such as \"File > New Tab\".")
        var path: String
    }

    let commands: Set<String>
    let propose: @Sendable (String) -> Void

    func call(arguments: Arguments) async throws -> String {
        guard commands.contains(arguments.path) else {
            return "That path is not in the list. Do not propose a command; describe the step in one sentence instead."
        }
        propose(arguments.path)
        return "Proposed. Tell the person in one short sentence what the command does; they confirm it with a button."
    }
}
