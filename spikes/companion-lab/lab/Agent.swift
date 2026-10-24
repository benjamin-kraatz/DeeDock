import AppKit
import ApplicationServices
import FoundationModels

/// The app's menu bar as a universal, AX-pressable command surface.
enum MenuCommands {
    /// Enabled leaf items as "Menu > Item" paths. Bounded: some apps (Ghostty) take seconds to walk.
    static func list(pid: pid_t, limit: Int = 140, budget: TimeInterval = 0.4) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let bar = AX.element(app, kAXMenuBarAttribute) else { return [] }
        let deadline = Date().addingTimeInterval(budget)
        var result: [String] = []
        for top in AX.children(bar).dropFirst() {              // skip the Apple menu
            guard let title = AX.copy(top, kAXTitleAttribute) as? String else { continue }
            walk(top, path: [title], into: &result, limit: limit, deadline: deadline)
            if result.count >= limit || Date() > deadline { break }
        }
        return result
    }

    private static func walk(_ element: AXUIElement, path: [String], into result: inout [String], limit: Int, deadline: Date) {
        for child in AX.children(element) {
            if result.count >= limit || Date() > deadline { return }
            let role = AX.copy(child, kAXRoleAttribute) as? String
            if role == "AXMenu" { walk(child, path: path, into: &result, limit: limit, deadline: deadline); continue }
            guard role == "AXMenuItem", let title = AX.copy(child, kAXTitleAttribute) as? String, !title.isEmpty else { continue }
            let submenu = AX.children(child).first { (AX.copy($0, kAXRoleAttribute) as? String) == "AXMenu" }
            if let submenu { walk(submenu, path: path + [title], into: &result, limit: limit, deadline: deadline) }
            else if (AX.copy(child, kAXEnabledAttribute) as? Bool) == true { result.append((path + [title]).joined(separator: " > ")) }
        }
    }

    /// Presses the item at `path`. Returns false when the path no longer resolves or is disabled.
    static func press(pid: pid_t, path: String) -> Bool {
        let parts = path.components(separatedBy: " > ")
        let app = AXUIElementCreateApplication(pid)
        guard var current = AX.element(app, kAXMenuBarAttribute) else { return false }
        for part in parts {
            var candidates = AX.children(current)
            if let menu = candidates.first(where: { (AX.copy($0, kAXRoleAttribute) as? String) == "AXMenu" }) { candidates = AX.children(menu) }
            guard let next = candidates.first(where: { (AX.copy($0, kAXTitleAttribute) as? String) == part }) else { return false }
            current = next
        }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
    }
}

/// Proposes, never runs, a menu command. The user confirms in the answer card.
struct ProposeMenuCommand: Tool {
    let name = "propose_menu_command"
    let description = "Propose one menu command for the user to run in the app. Only when the user asks you to DO something in the app. Use an exact path from the list."

    @Generable
    struct Arguments {
        @Guide(description: "Exact path from the menu list, e.g. \"File > New Tab\"")
        var path: String
    }

    let propose: @Sendable (String) -> Void

    func call(arguments: Arguments) async throws -> String {
        propose(arguments.path)
        return "Proposed \(arguments.path). Tell the user in one short sentence that they can confirm it with the button."
    }
}

@MainActor
final class CompanionAgent {
    private var session: LanguageModelSession?

    var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: "available"
        case .unavailable(let reason): "unavailable (\(reason))"
        }
    }

    func respond(request: String, context: CompanionContext?, appName: String, menu: [String],
                 propose: @escaping @Sendable (String) -> Void, update: @escaping (String) -> Void) async throws {
        let model = SystemLanguageModel.default
        let tools: [any Tool] = menu.isEmpty ? [] : [ProposeMenuCommand(propose: propose)]
        let instructions = """
        You are a tiny assistant that lives on top of the user's \(appName) window. Be concise: at most five short \
        sentences or a short list. Answer in the language the user writes in. When asked to translate, rewrite, fix \
        or reply, output only the resulting text with no preamble.
        \(menu.isEmpty ? "" : "Menu commands available in \(appName) (only for propose_menu_command):\n" + menu.joined(separator: "\n"))
        """
        let session = LanguageModelSession(model: model, tools: tools, instructions: instructions)
        self.session = session
        let contextText = String((context?.text ?? "").prefix(6_000))
        let image = model.capabilities.contains(.vision) ? context?.image : nil
        let stream = session.streamResponse {
            request
            if !contextText.isEmpty { "\nContext from \(appName):\n\"\"\"\n\(contextText)\n\"\"\"" }
            if let image { Attachment(image).label("What the user selected in \(appName)") }
        }
        for try await partial in stream { update(partial.content) }
    }
}
