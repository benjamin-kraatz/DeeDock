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

    static var crowdedItems: [DockItem] {
        (0..<30).map { item("app\($0)", name: "Sample \($0)", symbol: "app.fill", pinned: $0 < 25, running: $0 % 2 == 0) }
    }
    static var longNameItems: [DockItem] {
        [item("long", name: "A Sample Application With a Much Longer Display Name", symbol: "text.alignleft", pinned: true, running: true)] + items
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
    @State private var sections: DockSectionState

    init(items: [DockItem]? = nil, errorMessage: LocalizedStringResource? = nil,
         reduceMotion: Bool = false, reduceTransparency: Bool = false, magnified: Bool = false, dragProposal: DockDragProposal? = nil, dragMessage: LocalizedStringResource? = nil, settings: DockSettings = .defaults, availableLength: CGFloat = 800, expanded: Bool = false) {
        let items = items ?? DockPreviewData.items
        self.items = items
        self.errorMessage = errorMessage
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        let interaction = DockInteraction()
        interaction.dragProposal = dragProposal
        interaction.dragMessage = dragMessage
        interaction.dragActive = dragProposal != nil || dragMessage != nil
        let sections = DockSectionState()
        sections.configure(settings.appVisibility)
        if expanded { sections.toggle() }
        let entries = DockSectionProjection.entries(items: items, visibility: settings.appVisibility, expanded: sections.isExpanded)
        let slots = DockRenderSlot.slots(entries: entries, proposal: dragProposal)
        interaction.tooltipPreset = settings.tooltipPreset
        interaction.idleFade.configure(settings, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        sections.didChange = { [weak interaction, weak sections] in
            guard let interaction, let sections else { return }
            let entries = DockSectionProjection.entries(items: items, visibility: settings.appVisibility, expanded: sections.isExpanded)
            let slots = DockRenderSlot.slots(entries: entries, proposal: dragProposal)
            interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: slots.filter(\.isPinned).count,
                availableLength: availableLength, settings: settings)
        }
        _sections = State(initialValue: sections)
        interaction.runningIndicatorStyle = settings.runningIndicatorStyle
        interaction.layout = DockGeometry.layout(count: slots.count, favoriteCount: slots.filter(\.isPinned).count,
                                                  availableLength: availableLength, settings: settings)
        if magnified, let x = interaction.layout.restingCenters.first {
            interaction.pointer = settings.edge.point(CGPoint(x: x, y: interaction.layout.panelDepth - 36), depth: interaction.layout.panelDepth)
        }
        _interaction = State(initialValue: interaction)
    }

    var body: some View {
        let entries = DockSectionProjection.entries(items: items, visibility: sections.visibility, expanded: sections.isExpanded)
        DockContentView(items: items, entries: entries, launchingIDs: [], selectedTarget: entries.first?.target, keyboardFocus: true,
                        errorMessage: errorMessage, interaction: interaction,
                        reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                        openApp: { _ in }, togglePin: { _ in }, dismissError: {})
            .padding(20)
            .onAppear { interaction.toggleSection = { sections.toggle() } }
            .onDisappear { interaction.toggleSection = nil; interaction.tooltips.clear() }
    }
}
#endif
