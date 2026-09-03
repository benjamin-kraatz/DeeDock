import AppKit

/// Transient document feedback and spring activation, separate from pin editing and persistence.
@MainActor
final class DockDocumentDragState {
    private(set) var displayID: String?
    private(set) var item: DockItem?
    private var spring = DockSpringTarget()
    private var visit = UUID()
    var targetKey: String? { spring.target }

    func update(at point: CGPoint, candidate: DockPanelController?, nativeDisplayID: String?,
                panels: [String: DockPanelController]) {
        let target = candidate?.store.displayID == nativeDisplayID ? candidate?.documentTarget(at: point) : nil
        item = target
        displayID = target == nil ? nil : candidate?.store.displayID
        let key = target.flatMap { item in displayID.map { "\($0):\(item.id)" } }
        if spring.update(key) { visit = UUID() }
        for panel in panels.values {
            panel.updateSectionDragHover(at: point, valid: candidate === panel, documents: true)
            let selected = panel.store.displayID == displayID ? target : nil
            panel.setDragPresentation(proposal: nil, source: nil, targeted: candidate === panel,
                message: candidate === panel ? selected.map { .dragOpenIn(appName: $0.reference.name) } ?? .dragDocumentTarget : nil)
            panel.interaction.documentTargetID = selected?.id
            if selected == nil { panel.interaction.springEmphasized = false }
        }
    }

    func activate(on panel: DockPanelController) {
        guard panel.store.displayID == displayID, let item, spring.activate() else { return }
        let visit = visit
        panel.store.springOpen(item) { [weak self] in self?.visit == visit && self?.targetKey != nil }
    }

    func clear() {
        item = nil; displayID = nil
        spring.update(nil)
        visit = UUID()
    }
}
