import AppKit

/// Transient document feedback and the advertised handoff intent, separate from pin editing.
@MainActor
final class DockDocumentDragState {
    private(set) var displayID: String?
    private(set) var item: DockItem?
    private var targetKey: String?
    /// Once a target visit advertises window selection, losing that capability cannot turn
    /// the same drop into an app-level open. Leaving the target starts a new visit.
    private(set) var requiresWindowChoice = false

    /// Resolves direct application hits before any destination owns presentation.
    ///
    /// Folder-only Finder drags can be both document and pin payloads. In that case the
    /// document path presents only over an application; the pin path owns every insertion gap.
    /// - Returns: Whether document presentation owns this pointer update.
    @discardableResult
    func update(at point: CGPoint, candidate: DockPanelController?, nativeDisplayID: String?,
                panels: [String: DockPanelController], presentsFallback: Bool) -> Bool {
        let target = candidate?.store.displayID == nativeDisplayID ? candidate?.documentTarget(at: point) : nil
        item = target
        displayID = target == nil ? nil : candidate?.store.displayID
        let key = target.flatMap { item in displayID.map { "\($0):\(item.id)" } }
        if targetKey != key {
            targetKey = key
            requiresWindowChoice = false
        }
        let supportsPeek = target?.isRunning == true
            && target.flatMap { candidate?.windowPeekContext(for: $0.id) }?.settings.windowPeekEnabled == true
        requiresWindowChoice = requiresWindowChoice || supportsPeek
        let ownsPresentation = target != nil || presentsFallback
        guard ownsPresentation else {
            for panel in panels.values {
                panel.interaction.documentTargetID = nil
                panel.interaction.springEmphasized = false
            }
            return false
        }
        for panel in panels.values {
            panel.updateSectionDragHover(at: point, valid: candidate === panel, documents: true)
            let selected = panel.store.displayID == displayID ? target : nil
            let message: LocalizedStringResource = selected.map { item in
                if requiresWindowChoice {
                    return supportsPeek ? .fileRouteHover : .fileRouteDestinationUnavailable
                }
                return .dragOpenIn(appName: item.reference.name)
            } ?? .dragDocumentTarget
            panel.setDragPresentation(proposal: nil, source: nil, targeted: candidate === panel,
                                      message: candidate === panel ? message : nil)
            panel.interaction.documentTargetID = selected?.id
            if selected == nil { panel.interaction.springEmphasized = false }
        }
        return true
    }

    func clear() {
        item = nil; displayID = nil
        targetKey = nil
        requiresWindowChoice = false
    }
}
