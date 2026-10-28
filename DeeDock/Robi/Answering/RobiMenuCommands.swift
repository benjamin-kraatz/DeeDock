import ApplicationServices
import Foundation

/// The frontmost app's menu bar as commands Robi can propose, read once per interaction.
///
/// Every Mac app exposes its menus through Accessibility, Electron apps included, so this is the
/// one action surface that works everywhere. The spike counted 150 to 761 items per app, read in
/// 100 to 230 ms (Ghostty took 2.2 s), so the walk is bounded and runs off the main actor.
nonisolated enum RobiMenuCommands {
    static let separator = " > "

    /// Reads enabled leaf items as "Menu > Item" paths, skipping the Apple menu.
    ///
    /// Each top-level menu gets a fair share of what is left of `limit` and `budget` when its
    /// turn comes, so a long File menu cannot crowd out Window and Help. A menu that uses less
    /// leaves the rest to the menus after it.
    static func read(processIdentifier: pid_t, limit: Int = 400, budget: TimeInterval = 1.5) async -> RobiMenuCatalog {
        await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            guard let bar = RobiAX.element(application, kAXMenuBarAttribute) else { return RobiMenuCatalog(menus: [], isComplete: true) }
            let end = Date().addingTimeInterval(budget)
            let tops = RobiAX.children(bar).dropFirst().compactMap { top -> (String, AXUIElement)? in
                guard let title = RobiAX.value(top, kAXTitleAttribute) as? String, !title.isEmpty else { return nil }
                return (title, top)
            }
            var menus: [RobiMenuCatalog.Menu] = []
            var used = 0
            var isComplete = true
            for (offset, (title, top)) in tops.enumerated() {
                let left = tops.count - offset
                let quota = max(1, (limit - used) / left)
                let deadline = Date().addingTimeInterval(max(0, end.timeIntervalSinceNow) / Double(left))
                var paths: [String] = []
                let finished = walk(top, path: [title], into: &paths, limit: quota, deadline: deadline)
                isComplete = isComplete && finished
                used += paths.count
                menus.append(RobiMenuCatalog.Menu(title: title, paths: paths, isComplete: finished))
            }
            return RobiMenuCatalog(menus: menus, isComplete: isComplete)
        }.value
    }

    /// Collects leaf paths under `element`. Returns false when the quota or the time ran out first.
    private static func walk(_ element: AXUIElement, path: [String], into result: inout [String], limit: Int, deadline: Date) -> Bool {
        for child in RobiAX.children(element) {
            guard result.count < limit, Date() <= deadline else { return false }
            let role = RobiAX.value(child, kAXRoleAttribute) as? String
            if role == "AXMenu" {
                guard walk(child, path: path, into: &result, limit: limit, deadline: deadline) else { return false }
                continue
            }
            guard role == "AXMenuItem", let title = RobiAX.value(child, kAXTitleAttribute) as? String, !title.isEmpty else { continue }
            if let submenu = RobiAX.children(child).first(where: { (RobiAX.value($0, kAXRoleAttribute) as? String) == "AXMenu" }) {
                guard walk(submenu, path: path + [title], into: &result, limit: limit, deadline: deadline) else { return false }
            } else if (RobiAX.value(child, kAXEnabledAttribute) as? Bool) == true {
                result.append((path + [title]).joined(separator: separator))
            }
        }
        return true
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

/// The menu commands read from one app, grouped by top-level menu, and how the model sees them:
/// an overview in its instructions and further pages through `list_menu_commands`.
nonisolated struct RobiMenuCatalog: Sendable {
    struct Menu: Sendable {
        let title: String
        /// Full paths, such as "File > Export > PDF…", in menu order.
        let paths: [String]
        /// False when the read stopped before the end of this menu.
        let isComplete: Bool
    }

    /// How much of the catalog a model sees at once.
    struct Paging: Sendable {
        /// Commands shown for each menu in the instructions.
        let firstPage: Int
        /// Commands in each further page.
        let pageSize: Int

        /// Claude reads long instructions comfortably and pages without trouble.
        static let roomy = Paging(firstPage: 12, pageSize: 60)
        /// The on-device model has a small context: a glance at each menu, then small pages.
        static let tight = Paging(firstPage: 4, pageSize: 20)
    }

    let menus: [Menu]
    /// False when the read stopped early in any menu.
    let isComplete: Bool

    static let empty = RobiMenuCatalog(menus: [], isComplete: true)

    var isEmpty: Bool { menus.allSatisfy(\.paths.isEmpty) }

    /// Every path read, for checking a proposal. Includes paths the model has not been shown.
    var allPaths: Set<String> { Set(menus.flatMap(\.paths)) }

    /// Each menu with its count and its first commands, for the model's instructions.
    func overview(_ paging: Paging) -> String {
        var lines: [String] = []
        for menu in menus where !menu.paths.isEmpty {
            let count = menu.isComplete ? "\(menu.paths.count)" : "\(menu.paths.count)+"
            lines.append("\(menu.title) (\(count) commands):")
            lines.append(contentsOf: menu.paths.prefix(paging.firstPage))
            let rest = menu.paths.count - paging.firstPage
            if rest > 0 { lines.append("… \(rest) more in \(menu.title), next cursor \(paging.firstPage)") }
        }
        if !isComplete { lines.append("Some menus were too long to read in full.") }
        return lines.joined(separator: "\n")
    }

    /// One page of one menu, found by its title in any case, as the tool returns it.
    func page(menu title: String, cursor: Int, _ paging: Paging) -> String {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let menu = menus.first(where: { $0.title.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            let names = menus.filter { !$0.paths.isEmpty }.map(\.title).joined(separator: ", ")
            return "There is no menu named \(wanted). The menus are: \(names)."
        }
        let start = min(max(0, cursor), menu.paths.count)
        let slice = menu.paths[start..<min(start + paging.pageSize, menu.paths.count)]
        guard !slice.isEmpty else { return "No more commands in \(menu.title)." }
        var text = slice.joined(separator: "\n")
        let rest = menu.paths.count - (start + slice.count)
        if rest > 0 {
            text += "\n… \(rest) more, next cursor \(start + slice.count)"
        } else if !menu.isComplete {
            text += "\nThat is all Robi could read of \(menu.title)."
        }
        return text
    }
}
