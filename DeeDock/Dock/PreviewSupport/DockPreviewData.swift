#if DEBUG
import SwiftUI

/// Deterministic fixture values; never resolves installed applications or touches preferences.
@MainActor
enum DockPreviewData {
    static var items: [DockItem] {
        [item("notes", name: "Sample Notes", symbol: "note.text", pinned: true, running: true),
         item("browser", name: "Sample Browser", symbol: "globe", pinned: true, running: false),
         item("missing", name: "Unavailable Sample", symbol: "questionmark.app.dashed", pinned: true, running: false, available: false),
         item("terminal", name: "Sample Terminal", symbol: "terminal", pinned: false, running: true)]
    }

    private static func item(_ id: String, name: String, symbol: String, pinned: Bool,
                             running: Bool, available: Bool = true) -> DockItem {
        DockItem(reference: ApplicationReference(bundleIdentifier: "preview.\(id)",
                                                 url: URL(fileURLWithPath: "/Preview/\(id).app"), name: name),
                 icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
                 isFavorite: pinned, isRunning: running, isAvailable: available)
    }
}

/// A preview-only host with inert actions and no store, event monitors, or workspace service.
struct DockPreviewContent: View {
    private let items: [DockItem]
    private let errorMessage: LocalizedStringResource?
    private let reduceMotion: Bool
    private let reduceTransparency: Bool
    @State private var interaction: DockInteraction

    init(items: [DockItem]? = nil, errorMessage: LocalizedStringResource? = nil,
         reduceMotion: Bool = false, reduceTransparency: Bool = false, magnified: Bool = false, dragProposal: DockDragProposal? = nil, dragMessage: LocalizedStringResource? = nil, settings: DockSettings = .defaults) {
        let items = items ?? DockPreviewData.items
        self.items = items
        self.errorMessage = errorMessage
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        let interaction = DockInteraction()
        interaction.dragProposal = dragProposal
        interaction.dragMessage = dragMessage
        interaction.dragActive = dragProposal != nil || dragMessage != nil
        let slots = DockRenderSlot.slots(items: items, proposal: dragProposal)
        interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: slots.filter(\.isPinned).count,
                                                  availableWidth: 800, settings: settings)
        if magnified, let x = interaction.layout.restingCenters.first {
            interaction.pointer = CGPoint(x: x, y: interaction.layout.panelHeight - 36)
        }
        _interaction = State(initialValue: interaction)
    }

    var body: some View {
        DockContentView(items: items, launchingIDs: [], selectedID: items.first?.id, keyboardFocus: true,
                        errorMessage: errorMessage, interaction: interaction,
                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                        openApp: { _ in }, togglePin: { _ in }, dismissError: {})
            .padding(20)
    }
}
#endif
