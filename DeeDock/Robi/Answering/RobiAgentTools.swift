import Foundation
import FoundationModels
import Synchronization

/// The tools Robi's model may call. One browses the menu bar; the others propose steps.
///
/// None of them acts on the app. A proposed step lands in `RobiStepCollector`, which shows it on
/// the card, and runs only when the person clicks Run. Each tool checks its argument against what
/// Robi read: a menu path the catalog holds, or a window element of the right kind. Anything else
/// is refused with a short reason, so the model cannot invent a target.
enum RobiAgentTools {
    /// The tools for one request, or none when the intent cannot act or there is nothing to act on.
    nonisolated static func make(catalog: RobiMenuCatalog, paging: RobiMenuCatalog.Paging,
                                 actionable: [RobiLandmark], collector: RobiStepCollector) -> [any Tool] {
        var tools: [any Tool] = []
        if !catalog.isEmpty {
            tools.append(RobiListMenuCommands(catalog: catalog, paging: paging))
            tools.append(RobiProposeMenuCommand(paths: catalog.allPaths, collector: collector))
        }
        let byID = Dictionary(uniqueKeysWithValues: actionable.map { ($0.id, $0) })
        if actionable.contains(where: { RobiProposePress.kinds.contains($0.kind) }) {
            tools.append(RobiProposePress(landmarks: byID, collector: collector))
        }
        if actionable.contains(where: { RobiProposeToggle.kinds.contains($0.kind) }) {
            tools.append(RobiProposeToggle(landmarks: byID, collector: collector))
        }
        if actionable.contains(where: \.kind.isEditable) {
            tools.append(RobiProposeType(landmarks: byID, collector: collector))
        }
        return tools
    }
}

/// Gathers the steps the model proposes during one answer, in the order it proposes them, and
/// hands each new proposal to the card.
///
/// Tool calls may arrive on any thread and, with Claude, in parallel, so the steps sit behind a
/// lock. The model is told to propose steps one call at a time, in running order.
nonisolated final class RobiStepCollector: Sendable {
    private let steps = Mutex<[RobiStep]>([])
    private let publish: @Sendable (RobiProposal) -> Void

    init(publish: @escaping @Sendable (RobiProposal) -> Void) {
        self.publish = publish
    }

    /// Adds `step` and returns what the tool tells the model.
    func add(_ step: RobiStep) -> String {
        let added: [RobiStep]? = steps.withLock { steps in
            guard steps.count < RobiProposal.maximumSteps else { return nil }
            if steps.last == step { return steps }
            steps.append(step)
            return steps
        }
        guard let added else {
            return "There are already \(RobiProposal.maximumSteps) steps, the most one click runs. Do not propose more."
        }
        publish(RobiProposal(steps: added))
        let left = RobiProposal.maximumSteps - added.count
        return "Added as step \(added.count). \(left) more allowed. When the steps are complete, tell the person in one short sentence what they will do; they run them with one click. Never say they are done."
    }
}

/// Pages through one top-level menu of the app.
nonisolated struct RobiListMenuCommands: Tool {
    let name = "list_menu_commands"
    let description = "List more commands from one of the app's menus, a page at a time. Use it when the command you need is not among those already shown."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "A top-level menu's name exactly as listed, such as \"View\".")
        var menu: String
        @Guide(description: "Where the page starts: the next cursor a listing gave, or 0 for the start of the menu.")
        var cursor: Int
    }

    let catalog: RobiMenuCatalog
    let paging: RobiMenuCatalog.Paging

    func call(arguments: Arguments) async throws -> String {
        catalog.page(menu: arguments.menu, cursor: arguments.cursor, paging)
    }
}

/// Proposes one of the app's menu commands as a step.
nonisolated struct RobiProposeMenuCommand: Tool {
    let name = "propose_menu_command"
    let description = "Propose one of the app's menu commands as the next step. Use it only when the person asks you to do something in the app, and only with an exact path from a listing."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The exact menu path from a listing, such as \"File > New Tab\".")
        var path: String
    }

    let paths: Set<String>
    let collector: RobiStepCollector

    func call(arguments: Arguments) async throws -> String {
        guard paths.contains(arguments.path) else {
            return "That path is not in the menu. Use list_menu_commands to find the exact path, or describe the step in one sentence instead."
        }
        return collector.add(.menu(path: arguments.path))
    }
}

/// Proposes pressing a button or link in the window.
nonisolated struct RobiProposePress: Tool {
    static let kinds: Set<RobiLandmark.Kind> = [.button, .link]

    let name = "propose_press"
    let description = "Propose pressing a button or link in the window as the next step, by its element number."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The element's number from the context, such as 12 for [#12 button …].")
        var element: Int
    }

    let landmarks: [Int: RobiLandmark]
    let collector: RobiStepCollector

    func call(arguments: Arguments) async throws -> String {
        guard let landmark = landmarks[arguments.element], Self.kinds.contains(landmark.kind) else {
            return "Element \(arguments.element) is not a button or link Robi can press. Pick another, or describe the step in one sentence."
        }
        return collector.add(.press(element: landmark.id, label: landmark.label))
    }
}

/// Proposes turning a checkbox or switch on or off, or selecting an option.
nonisolated struct RobiProposeToggle: Tool {
    static let kinds: Set<RobiLandmark.Kind> = [.checkbox, .option]

    let name = "propose_toggle"
    let description = "Propose turning a checkbox or switch on or off, or selecting an option, as the next step, by its element number."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The element's number from the context.")
        var element: Int
        @Guide(description: "true to turn it on or select it, false to turn it off.")
        var on: Bool
    }

    let landmarks: [Int: RobiLandmark]
    let collector: RobiStepCollector

    func call(arguments: Arguments) async throws -> String {
        guard let landmark = landmarks[arguments.element], Self.kinds.contains(landmark.kind) else {
            return "Element \(arguments.element) is not a checkbox, switch or option. Pick another, or describe the step in one sentence."
        }
        // Selecting an option is a click on it; an option cannot be turned off.
        if landmark.kind == .option {
            guard arguments.on else { return "An option cannot be turned off; select another option instead." }
            return collector.add(.press(element: landmark.id, label: landmark.label))
        }
        return collector.add(.toggle(element: landmark.id, label: landmark.label, on: arguments.on))
    }
}

/// Proposes replacing the text of a field or text area.
nonisolated struct RobiProposeType: Tool {
    let name = "propose_type"
    let description = "Propose replacing the text of a field or text area in the window as the next step, such as a search field before pressing Search."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The field's number from the context.")
        var element: Int
        @Guide(description: "The complete text the field should hold afterwards.")
        var text: String
    }

    let landmarks: [Int: RobiLandmark]
    let collector: RobiStepCollector

    func call(arguments: Arguments) async throws -> String {
        guard let landmark = landmarks[arguments.element], landmark.kind.isEditable else {
            return "Element \(arguments.element) is not a field Robi can type into. Pick another, or describe the step in one sentence."
        }
        return collector.add(.type(element: landmark.id, label: landmark.label, text: arguments.text))
    }
}
