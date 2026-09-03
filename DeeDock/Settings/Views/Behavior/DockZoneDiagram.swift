import SwiftUI

/// Shares placement and trigger geometry with live docks and the Position diagram.
struct DockZoneDiagram: View {
    let settings: DockSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DockDisplayDiagram(settings: settings, showsActivation: true)
            Text(.behaviorDiagramLegend).font(.caption).foregroundStyle(.secondary)
        }
    }
}
